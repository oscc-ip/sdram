#![allow(non_snake_case)]
#![allow(unused_variables)]

use crate::drive::Driver;
use crate::{OfflineArgs, AXI_SIZE};
use common::plusarg::PlusArgMatcher;
use common::MEM_SIZE;
use core::mem;
use rand::Rng;
use std::ffi::*;
use std::sync::Mutex;
use svdpi::SvScope;
use tracing::{debug, error, info, trace};

pub type SvBitVecVal = u32;

// --------------------------
// preparing data structures
// --------------------------

static DPI_TARGET: Mutex<Option<Box<Driver>>> = Mutex::new(None);
static AWID: Mutex<u8> = Mutex::new(0);

pub trait ToBytes {
    fn to_bytes(&self) -> Vec<u8>;
}

impl ToBytes for u32 {
    fn to_bytes(&self) -> Vec<u8> {
        self.to_le_bytes().to_vec()
    }
}

impl ToBytes for Vec<u32> {
    fn to_bytes(&self) -> Vec<u8> {
        self.iter().flat_map(|&value| value.to_bytes()).collect()
    }
}

#[derive(Clone, Debug)]
pub(crate) struct AxiWritePayload {
    pub(crate) id: u8,
    pub(crate) len: u8,
    pub(crate) addr: u32,
    pub(crate) data: Vec<u32>,
    pub(crate) strb: Vec<u8>,
    pub(crate) wUser: Vec<u8>,
    pub(crate) awUser: u8,
    pub(crate) dataValid: u8,
    pub(crate) burst: u8,
    pub(crate) cache: u8,
    pub(crate) lock: u8,
    pub(crate) prot: u8,
    pub(crate) qos: u8,
    pub(crate) region: u8,
    pub(crate) size: u8,
}

impl AxiWritePayload {
    pub(crate) fn random() -> Self {
        let mut rng = rand::thread_rng();
        let burst_type = rng.gen_range(0..=2);
        let burst_length = if burst_type == 2 {
            1 << rng.gen_range(1..=4)
        } else {
            rng.gen_range(0..=15)
        };
        let burst_size: u8 = rng.gen_range(0..=7 - AXI_SIZE.leading_zeros()) as u8;
        let bytes_number = 1 << burst_size;
        let payload = AxiWritePayload {
            id: *AWID.lock().unwrap(),
            len: burst_length,
            addr: rng.gen_range(0xfc000000..=u32::MAX as u32) / bytes_number * bytes_number,
            data: (0..100).map(|_| rng.gen_range(0..=u32::MAX)).collect(),
            strb: (0..100).map(|_| (1 << (burst_size + 1)) - 1).collect(),
            wUser: (0..100).map(|_| rng.gen_range(0..=u8::MAX)).collect(),
            awUser: rng.gen_range(0..=u8::MAX),
            dataValid: 1,
            burst: burst_type,
            cache: 0x77,
            lock: 0x88,
            prot: 0x99,
            qos: 0xaa,
            region: 0xbb,
            size: burst_size,
        };
        *AWID.lock().unwrap() += 1;
        payload
    }
}

impl ToBytes for AxiWritePayload {
    fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.push(self.size);
        bytes.push(self.region);
        bytes.push(self.qos);
        bytes.push(self.prot);
        bytes.push(self.lock);
        bytes.push(self.cache);
        bytes.push(self.burst);
        bytes.push(self.dataValid);
        bytes.push(self.awUser);
        bytes.extend(self.wUser.iter());
        bytes.extend(self.strb.iter());
        bytes.extend(self.data.to_bytes());
        bytes.extend(&self.addr.to_bytes());
        bytes.push(self.len);
        bytes.push(self.id);
        bytes
    }
}

#[derive(Clone, Debug)]
pub(crate) struct AxiReadPayload {
    pub(crate) addr: u32,
    pub(crate) id: u8,
    pub(crate) user: u8,
    pub(crate) burst: u8,
    pub(crate) cache: u8,
    pub(crate) len: u8,
    pub(crate) lock: u8,
    pub(crate) prot: u8,
    pub(crate) qos: u8,
    pub(crate) region: u8,
    pub(crate) size: u8,
    pub(crate) valid: u8,
}

impl AxiReadPayload {
    pub(crate) fn random() -> Self {
        let mut rng = rand::thread_rng();
        AxiReadPayload {
            addr: rng.gen_range(0..=255),
            id: rng.gen_range(0..=255),
            user: rng.gen_range(0..=255),
            burst: rng.gen_range(0..=15),
            cache: rng.gen_range(0..=15),
            len: rng.gen_range(0..=255),
            lock: rng.gen_range(0..=1),
            prot: rng.gen_range(0..=7),
            qos: rng.gen_range(0..=15),
            region: rng.gen_range(0..=15),
            size: rng.gen_range(0..=15),
            valid: 1,
        }
    }
    pub(crate) fn from_write_payload(payload: &AxiWritePayload) -> Self {
        AxiReadPayload {
            addr: payload.addr,
            id: payload.id,
            user: payload.awUser,
            burst: payload.burst,
            cache: payload.cache,
            len: payload.len,
            lock: payload.lock,
            prot: payload.prot,
            qos: payload.qos,
            region: payload.region,
            size: payload.size,
            valid: 1,
        }
    }
}

impl ToBytes for AxiReadPayload {
    fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.push(self.valid);
        bytes.push(self.size);
        bytes.push(self.region);
        bytes.push(self.qos);
        bytes.push(self.prot);
        bytes.push(self.lock);
        bytes.push(self.len);
        bytes.push(self.cache);
        bytes.push(self.burst);
        bytes.push(self.user);
        bytes.push(self.id);
        bytes.extend(&self.addr.to_bytes());
        bytes
    }
}

unsafe fn write_to_pointer(dst: *mut u8, data: &[u8]) {
    std::ptr::copy_nonoverlapping(data.as_ptr(), dst, data.len());
}

unsafe fn fill_axi_payload<T: ToBytes>(dst: *mut SvBitVecVal, payload: &T) {
    let data = payload.to_bytes();
    // info!("data length: {:?}", data.len());
    write_to_pointer(dst as *mut u8, &data);
}

//----------------------
// dpi functions
//----------------------

/// evaluate at R fire.
#[no_mangle]
unsafe extern "C" fn axi_read_done_axi4Probe(
    rdata: [u32; 100],
    rid: u8,
    rlast: u8,
    rresp: u8,
    ruser: u8,
) {
    let mut driver = DPI_TARGET.lock().unwrap();
    let driver = driver.as_mut().unwrap();
    driver.axi_read_done(rdata.to_vec(), rid, rlast, rresp, ruser);
}

/// evaluate at AW ready.
#[no_mangle]
unsafe extern "C" fn axi_write_ready_axi4Probe(payload: *mut SvBitVecVal) {
    debug!("axi_write_ready_axi4Probe");
    let mut driver = DPI_TARGET.lock().unwrap();
    let driver = driver.as_mut().unwrap();
    let response = driver.axi_write_ready();
    fill_axi_payload(payload, &response);
}

/// evaluate at B fire.
#[no_mangle]
unsafe extern "C" fn axi_write_done_axi4Probe(bid: c_uchar, bresp: c_uchar, buser: c_uchar) {
    debug!("axi_write_ready_axi4Probe (bid={bid}, bresp={bresp}, buser={buser})");
    let mut driver = DPI_TARGET.lock().unwrap();
    let driver = driver.as_mut().unwrap();
    driver.axi_write_done(bid as u8, bresp as u8, buser as u8);
}

/// evaluate at AR ready.
#[no_mangle]
unsafe extern "C" fn axi_read_ready_axi4Probe(payload: *mut SvBitVecVal) {
    debug!("axi_read_ready_axi4Probe");
    let mut driver = DPI_TARGET.lock().unwrap();
    let driver = driver.as_mut().unwrap();
    let response = driver.axi_read_ready();
    fill_axi_payload(payload, &response);
}

#[no_mangle]
unsafe extern "C" fn cosim_watchdog(reason: *mut c_char) {
    let mut driver = DPI_TARGET.lock().unwrap();
    if let Some(driver) = driver.as_mut() {
        *reason = driver.watchdog() as c_char;
    }
}

#[no_mangle]
unsafe extern "C" fn cosim_init() {
    println!("cosim_init called");

    let plusargs = PlusArgMatcher::from_args();
    let args = OfflineArgs::from_plusargs(&plusargs);
    args.common_args.setup_logger().unwrap();

    let scope = SvScope::get_current().expect("failed to get scope in cosim_init");

    let driver = Box::new(Driver::new(scope, &args));
    let mut dpi_target = DPI_TARGET.lock().unwrap();
    assert!(
        dpi_target.is_none(),
        "cosim_init should be called only once"
    );
    *dpi_target = Some(driver);

    if let Some(driver) = dpi_target.as_mut() {
        driver.init();
    }
}

//--------------------------------
// import functions and wrappers
//--------------------------------

mod dpi_export {
    use std::ffi::*;

    extern "C" {
        #[cfg(feature = "trace")]
        /// `export "DPI-C" function dump_wave(input string file)`
        pub fn dump_wave(path: *const c_char);
    }
}

#[cfg(feature = "trace")]
pub(crate) fn dump_wave(scope: svdpi::SvScope, path: &str) {
    use svdpi;
    let path_cstring = CString::new(path).unwrap();

    svdpi::set_scope(scope);
    unsafe {
        dpi_export::dump_wave(path_cstring.as_ptr());
    }
}
