#![allow(non_snake_case)]
#![allow(unused_variables)]

use crate::drive::Driver;
use crate::{OfflineArgs, AXI_SIZE};
use common::plusarg::PlusArgMatcher;
use once_cell::sync::Lazy;
use rand::prelude::SliceRandom;
use rand::rngs::StdRng;
use rand::{Rng, SeedableRng};
use std::ffi::*;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};
use svdpi::SvScope;
use tracing::{info, trace};

pub type SvBitVecVal = u32;

// --------------------------
// preparing data structures
// --------------------------

static DPI_TARGET: Mutex<Option<Box<Driver>>> = Mutex::new(None);
static AWID: Mutex<u8> = Mutex::new(0);

pub trait ToBytes {
    fn to_bytes(&self) -> Vec<u8>;
}

pub trait ToBytesBe {
    fn to_bytes_be(&self) -> Vec<u8>;
}

impl ToBytes for u32 {
    fn to_bytes(&self) -> Vec<u8> {
        self.to_le_bytes().to_vec()
    }
}

impl ToBytesBe for u32 {
    fn to_bytes_be(&self) -> Vec<u8> {
        self.to_be_bytes().to_vec()
    }
}

impl ToBytes for Vec<u32> {
    fn to_bytes(&self) -> Vec<u8> {
        self.iter().flat_map(|&value| value.to_bytes()).collect()
    }
}

impl ToBytesBe for Vec<u32> {
    fn to_bytes_be(&self) -> Vec<u8> {
        self.iter().flat_map(|&value| value.to_bytes_be()).collect()
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

static RNG: Lazy<Arc<Mutex<StdRng>>> = Lazy::new(|| {
    let start = SystemTime::now();
    let since_epoch = start
        .duration_since(UNIX_EPOCH)
        .expect("Clock may have gone backwards");
    let seed = since_epoch.as_secs();
    info!("Using seed: {:#x}", seed);
    Arc::new(Mutex::new(StdRng::seed_from_u64(seed)))
});

impl AxiWritePayload {
    fn generate_random_strb(use_bit: u8, total_bit: u8, rng: &mut StdRng) -> u8 {
        let ones_count = 1 << use_bit;
        let zeros_count = (1 << total_bit) - ones_count;

        let mut bits: Vec<u8> = vec![1; ones_count as usize];
        bits.extend(vec![0; zeros_count as usize]);
        bits.shuffle(rng);

        let mut result = 0u8;
        for (i, &bit) in bits.iter().enumerate() {
            result |= bit << i;
        }

        result
    }
    pub(crate) fn random() -> Self {
        let mut rng = RNG.lock().unwrap();

        let burst_type = 1;
        // let burst_type = rng.gen_range(0..=2);
        let burst_length = match burst_type {
            0 => rng.gen_range(0..=15),
            1 => rng.gen_range(0..=u8::MAX),
            2 => 1 << rng.gen_range(1..=4),
            _ => 0,
        };
        let burst_width = AXI_SIZE >> 3;
        let MAX_BURST_WIDTH = 7 - burst_width.leading_zeros() as u8;
        // let burst_size = 0;
        let burst_size = rng.gen_range(0..=MAX_BURST_WIDTH);
        let bytes_number = 8 << (1 << burst_size);
        let total_bit = 1 << MAX_BURST_WIDTH;
        let used_bit = 1 << burst_size;
        let strb_sequence = {
            let mut vec: Vec<u8> = Vec::new();
            let mut start = (1 << used_bit) - 1;
            for i in 0..total_bit / used_bit {
                vec.push(start);
                start <<= used_bit;
            }
            vec
        };
        let payload = AxiWritePayload {
            id: *AWID.lock().unwrap() & 0xF,
            len: burst_length - 1,
            addr: rng.gen_range(0xfc000000..=u32::MAX) / bytes_number * bytes_number,
            data: (0..256).map(|_| rng.gen_range(0..=u32::MAX)).collect(),
            strb: (0..256)
                .map(|i| strb_sequence[i % strb_sequence.len()])
                .collect(),
            wUser: (0..256).map(|_| rng.gen_range(0..=u8::MAX)).collect(),
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
        vec![
            self.size,
            self.region,
            self.qos,
            self.prot,
            self.lock,
            self.cache,
            self.burst,
            self.dataValid,
            self.awUser,
        ]
        .into_iter()
        .chain(self.wUser.clone())
        .chain(self.strb.clone())
        .chain(self.data.to_bytes())
        .chain(self.addr.to_bytes())
        .chain(vec![self.len, self.id])
        .collect::<Vec<u8>>()
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
        vec![
            self.valid,
            self.size,
            self.region,
            self.qos,
            self.prot,
            self.lock,
            self.len,
            self.cache,
            self.burst,
            self.user,
            self.id,
        ]
        .into_iter()
        .chain(self.addr.to_bytes())
        .collect()
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
    rdata: *const u32,
    len: u8,
    last_data: u32,
    rid: u8,
    rresp: u8,
    ruser: u8,
) {
    let rdata_slice = std::slice::from_raw_parts(rdata, 256);
    let mut driver = DPI_TARGET.lock().unwrap();
    let driver = driver.as_mut().unwrap();
    driver.axi_read_done(rdata_slice.to_vec(), len, last_data, rid, rresp, ruser);
}

/// evaluate at AW ready.
#[no_mangle]
unsafe extern "C" fn axi_write_ready_axi4Probe(payload: *mut SvBitVecVal) {
    trace!("axi_write_ready_axi4Probe");
    let mut driver = DPI_TARGET.lock().unwrap();
    let driver = driver.as_mut().unwrap();
    let response = driver.axi_write_ready();
    fill_axi_payload(payload, &response);
}

/// evaluate at B fire.
#[no_mangle]
unsafe extern "C" fn axi_write_done_axi4Probe(bid: c_uchar, bresp: c_uchar, buser: c_uchar) {
    trace!("axi_write_done_axi4Probe (bid={bid}, bresp={bresp}, buser={buser})");
    let mut driver = DPI_TARGET.lock().unwrap();
    let driver = driver.as_mut().unwrap();
    driver.axi_write_done(bid, bresp, buser);
}

/// evaluate at AR ready.
#[no_mangle]
unsafe extern "C" fn axi_read_ready_axi4Probe(payload: *mut SvBitVecVal) {
    trace!("axi_read_ready_axi4Probe");
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
