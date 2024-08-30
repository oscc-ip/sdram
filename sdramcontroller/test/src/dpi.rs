#![allow(non_snake_case)]
#![allow(unused_variables)]

use clap::Parser;
use rand::Rng;
use std::ffi::*;
use std::sync::Mutex;
use tracing::debug;
use bytemuck::cast_slice;

use crate::drive::Driver;
use crate::svdpi::SvScope;
use crate::{OfflineArgs, AXI_SIZE};

pub type SvBitVecVal = u32;

// --------------------------
// preparing data structures
// --------------------------

static DPI_TARGET: Mutex<Option<Box<Driver>>> = Mutex::new(None);
static awid: Mutex<u8> = Mutex::new(0);

#[derive(Clone, Debug)]
pub(crate) struct AxiWritePayload {
    pub(crate) id: u8,
    pub(crate) len: u8,
    pub(crate) addr: u32,
    pub(crate) data: Vec<u32>,
    pub(crate) strb: Vec<u8>,
    pub(crate) wUser: Vec<u32>,
    pub(crate) awUser: u32,
    pub(crate) dataValid: bool,
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
            rng.gen_range(2..=8) * 2
        } else {
            rng.gen_range(0..=15)
        };
        let burst_size: u8 = rng.gen_range(0..=7 - AXI_SIZE.leading_zeros()) as u8;
        let bytes_number = 1 << burst_size;
        *awid.lock().unwrap() += 1;
        AxiWritePayload {
            id: *awid.lock().unwrap(),
            len: burst_length,
            addr: rng.gen_range(0..=u32::MAX) / bytes_number * bytes_number,
            data: (0..burst_length)
                .map(|_| rng.gen_range(0..=u32::MAX))
                .collect(),
            strb: (0..burst_length).map(|_| (1 << burst_size) - 1).collect(),
            wUser: (0..burst_length)
                .map(|_| rng.gen_range(0..=u32::MAX))
                .collect(),
            awUser: rng.gen_range(0..=u32::MAX),
            dataValid: true,
            burst: burst_type,
            cache: 0,
            lock: 0,
            prot: 0,
            qos: 0,
            region: 0,
            size: burst_size,
        }
    }
}

#[derive(Clone, Debug)]
pub(crate) struct AxiReadPayload {
    pub(crate) addr: u32,
    pub(crate) id: u8,
    pub(crate) user: u32,
    pub(crate) burst: u8,
    pub(crate) cache: u8,
    pub(crate) len: u8,
    pub(crate) lock: u8,
    pub(crate) prot: u8,
    pub(crate) qos: u8,
    pub(crate) region: u8,
    pub(crate) size: u8,
    pub(crate) valid: bool,
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
            valid: true,
        }
    }
    pub(crate) fn from_write_payload(payload: AxiWritePayload) -> Self {
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
            valid: true,
        }
    }
}

unsafe fn write_to_pointer(dst: *mut u8, data: &[u8]) {
    let dst = std::slice::from_raw_parts_mut(dst, data.len());
    dst.copy_from_slice(data);
}

unsafe fn fill_axi_read_payload(dst: *mut SvBitVecVal, dlen: u32, payload: &AxiReadPayload) {}

unsafe fn fill_axi_write_payload(dst: *mut SvBitVecVal, dlen: u32, payload: &AxiWritePayload) {
    let data_len = 256 * (dlen / 8) as usize;
    assert!(payload.data.len() <= data_len);
    write_to_pointer(dst as *mut u8, cast_slice(&payload.data));
}

//----------------------
// dpi functions
//----------------------

/// evaluate at R fire.
#[no_mangle]
unsafe extern "C" fn axi_read_resp_axi4Probe(
    rdata: c_longlong,
    rid: c_uchar,
    rlast: c_uchar,
    rresp: c_uchar,
    ruser: c_uchar,
) {
    debug!(
        "axi_read_resp_axi4Probe (rdata={rdata}, rid={rid}, rlast={rlast:#x}, \
  rresp={rresp}, ruser={ruser})"
    );
    let mut driver = DPI_TARGET.lock().unwrap();
    let driver = driver.as_mut().unwrap();
    driver.axi_read_resp(
        rdata as u32,
        rid as u8,
        rlast as u8,
        rresp as u8,
        ruser as u8,
    );
}

/// evaluate at AW ready.
#[no_mangle]
unsafe extern "C" fn axi_write_ready_axi4Probe(payload: *mut SvBitVecVal) {
    debug!("axi_write_ready_axi4Probe");
    let mut driver = DPI_TARGET.lock().unwrap();
    let driver = driver.as_mut().unwrap();
    let response = driver.axi_write_ready();
    fill_axi_write_payload(payload, driver.dlen, &response);
}

/// evaluate at B fire.
#[no_mangle]
unsafe extern "C" fn axi_write_done_axi4Probe(bid: c_uchar, bresp: c_uchar, buser: c_uchar) {
    debug!("axi_write_ready_axi4Probe (bid={bid}, bresp={bresp}, buser={buser})");
    let mut driver = DPI_TARGET.lock().unwrap();
    let driver = driver.as_mut().unwrap();
    driver.axi_write_done(bid as u8, bresp as u8, buser as u8);
}

/// evaluate at AW ready.
#[no_mangle]
unsafe extern "C" fn axi_read_ready_axi4Probe(payload: *mut SvBitVecVal) {
    debug!("axi_read_ready_axi4Probe");
    let mut driver = DPI_TARGET.lock().unwrap();
    let driver = driver.as_mut().unwrap();
    let response = driver.axi_read_ready();
    fill_axi_read_payload(payload, driver.dlen, &response);
}

#[no_mangle]
unsafe extern "C" fn cosim_init() {
    println!("cosim_init called");

    let args = OfflineArgs::parse();
    args.common_args.setup_logger().unwrap();

    let scope = SvScope::get_current().expect("failed to get scope in cosim_init");

    let driver = Box::new(Driver::new(scope, &args));
    let mut dpi_target = DPI_TARGET.lock().unwrap();
    assert!(
        dpi_target.is_none(),
        "cosim_init should be called only once"
    );
    *dpi_target = Some(driver);
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
pub(crate) fn dump_wave(scope: crate::svdpi::SvScope, path: &str) {
    use crate::svdpi;
    let path_cstring = CString::new(path).unwrap();

    svdpi::set_scope(scope);
    unsafe {
        dpi_export::dump_wave(path_cstring.as_ptr());
    }
}
