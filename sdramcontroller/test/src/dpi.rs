#![allow(non_snake_case)]
#![allow(unused_variables)]

use clap::Parser;
use rand::Rng;
use std::ffi::{c_char, c_longlong, c_uchar};
use std::sync::Mutex;
use tracing::debug;

use crate::drive::Driver;
use crate::svdpi::SvScope;
use crate::OfflineArgs;

pub type SvBitVecVal = u32;

// --------------------------
// preparing data structures
// --------------------------

static DPI_TARGET: Mutex<Option<Box<Driver>>> = Mutex::new(None);

#[derive(Clone, Debug)]
pub(crate) struct AxiWritePayload {
    pub(crate) id: Vec<u8>,
    pub(crate) len: u8,
    pub(crate) addr: u8,
    pub(crate) data: Vec<u8>,
    pub(crate) strb: Vec<u8>,
    pub(crate) wUser: Vec<u8>,
    pub(crate) awUser: Vec<u8>,
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
        AxiWritePayload {
            id: (0..8).map(|_| rng.gen_range(0..=255)).collect(),
            len: rng.gen_range(0..=255),
            addr: rng.gen_range(0..=255),
            data: (0..8).map(|_| rng.gen_range(0..=255)).collect(),
            strb: (0..8).map(|_| rng.gen_range(0..=255)).collect(),
            wUser: (0..8).map(|_| rng.gen_range(0..=255)).collect(),
            awUser: (0..8).map(|_| rng.gen_range(0..=255)).collect(),
            dataValid: true,
            burst: rng.gen_range(0..=15),
            cache: rng.gen_range(0..=15),
            lock: rng.gen_range(0..=1),
            prot: rng.gen_range(0..=7),
            qos: rng.gen_range(0..=15),
            region: rng.gen_range(0..=15),
            size: rng.gen_range(0..=15),
        }
    }
}

#[derive(Clone, Debug)]
pub(crate) struct AxiReadPayload {
    pub(crate) addr: u8,
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
}

unsafe fn write_to_pointer(dst: *mut u8, data: &[u8]) {
    let dst = std::slice::from_raw_parts_mut(dst, data.len());
    dst.copy_from_slice(data);
}

unsafe fn fill_axi_read_payload(dst: *mut SvBitVecVal, dlen: u32, payload: &AxiReadPayload) {}

unsafe fn fill_axi_write_payload(dst: *mut SvBitVecVal, dlen: u32, payload: &AxiWritePayload) {
    let data_len = 256 * (dlen / 8) as usize;
    assert!(payload.data.len() <= data_len);
    write_to_pointer(dst as *mut u8, &payload.data);
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
