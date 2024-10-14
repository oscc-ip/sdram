use common::MEM_SIZE;
use svdpi::{get_time, SvScope};
use tracing::{error, info, trace};

use crate::dpi::ToBytes;
use crate::dpi::*;
use crate::driver_assert_eq;
use crate::{OfflineArgs, AXI_SIZE};
use std::collections::VecDeque;

struct ShadowMem {
    mem: Vec<u8>,
}

impl ShadowMem {
    pub fn new() -> Self {
        Self {
            mem: vec![0; MEM_SIZE],
        }
    }

    fn is_addr_align(&self, addr: u32, size: u8) -> bool {
        let bytes_number = 1 << size;
        let aligned_addr = addr / bytes_number * bytes_number;
        addr == aligned_addr
    }

    // size: 1 << arsize
    // return: Vec<u8> with len=bus_size
    pub fn read_mem_axi(&self, payload: AxiReadPayload) -> Vec<u8> {
        let bytes_number: u32 = 1 << payload.size;

        let transfer_count: u32 = (payload.len + 1) as u32;

        let mut lower_boundary = 0;
        let mut upper_boundary = 0;

        let mut data: Vec<u8> = vec![];

        if payload.burst == 2 {
            lower_boundary =
                payload.addr / (bytes_number * transfer_count) * (bytes_number * transfer_count);
            upper_boundary = lower_boundary + bytes_number * transfer_count;
            assert!(
                payload.len == 2 || payload.len == 4 || payload.len == 8 || payload.len == 16,
                "unsupported burst len"
            );
        }

        let mut current_addr = payload.addr;
        assert!(
            self.is_addr_align(payload.addr, payload.size),
            "address is unaligned!"
        );

        for _ in 0..transfer_count {
            data.extend_from_slice(
                &self.mem[current_addr as usize..(current_addr + bytes_number) as usize],
            );

            current_addr = match payload.burst {
                0 => current_addr,                // FIXED
                1 => current_addr + bytes_number, // INCR
                2 => {
                    if current_addr + bytes_number >= upper_boundary {
                        lower_boundary
                    } else {
                        current_addr + bytes_number
                    }
                } // WRAP
                _ => {
                    panic!("unknown burst type: {:?}", payload.burst);
                }
            }
        }
        data
    }

    // size: 1 << awsize
    // bus_size: AXI bus width in bytes
    // masks: write strokes, len=bus_size
    // data: write data, len=bus_size
    pub fn write_mem_axi(&mut self, payload: AxiWritePayload) {
        let transfer_count = (payload.len + 1) as usize;

        // assert!(
        //     transfer_count == payload.data.len()
        //         && transfer_count == payload.strb.len(),
        //     "malformed payload: transfer_count = {:?}, payload.data.len = {:?}, payload.strb.len = {:?}",
        //     transfer_count, payload.data.len(), payload.strb.len(),
        // );

        let bytes_number: u32 = 1 << payload.size;

        let mut lower_boundary = 0;
        let mut upper_boundary = 0;
        if payload.burst == 2 {
            lower_boundary = payload.addr / (bytes_number * transfer_count as u32)
                * (bytes_number * transfer_count as u32);
            upper_boundary = lower_boundary + bytes_number * transfer_count as u32;
            assert!(
                transfer_count == 2
                    || transfer_count == 4
                    || transfer_count == 8
                    || transfer_count == 16,
                "unsupported burst len: {}",
                payload.len
            );
        }

        let mut current_addr = payload.addr;
        assert!(
            self.is_addr_align(payload.addr, payload.size),
            "address is unaligned!"
        );

        for item_idx in 0..transfer_count {
            if payload.strb[item_idx] == 0 {
                continue;
            }

            assert_eq!(
                payload.strb[item_idx].count_ones(),
                1 << payload.size >> 3,
                "the number of will write bytes is not equal"
            );

            info!(
                "writing({:#02x}) {:#08x} -> {:#08x}/{:#} with strb:{:#04b}",
                payload.id,
                payload.data[item_idx],
                current_addr,
                match payload.burst {
                    0 => "FIX",
                    1 => "INCR",
                    2 => "WARP",
                    _ => "UNKNOWN",
                },
                payload.strb[item_idx]
            );

            for (write_count, byte_idx) in (0..AXI_SIZE / 8).enumerate() {
                let byte_mask: bool = (payload.strb[item_idx] >> byte_idx) & 1 != 0;
                if byte_mask {
                    self.mem[(current_addr + write_count as u32 - 0xfc000000) as usize] =
                        (payload.data[item_idx] >> (byte_idx * 8) & 0xff) as u8;
                }
            }

            current_addr = match payload.burst {
                0 => current_addr,                // FIXED
                1 => current_addr + bytes_number, // INCR
                2 => {
                    if current_addr + bytes_number >= upper_boundary {
                        lower_boundary
                    } else {
                        current_addr + bytes_number
                    }
                } // WRAP
                _ => {
                    panic!("unknown burst type: {:?}", payload.burst);
                }
            }
        }
        info!("axi write finished.");
    }
}

pub(crate) struct Driver {
    // SvScope from cosim_init
    scope: SvScope,

    #[cfg(feature = "trace")]
    wave_path: String,
    #[cfg(feature = "trace")]
    dump_start: u64,
    #[cfg(feature = "trace")]
    dump_end: u64,
    #[cfg(feature = "trace")]
    dump_started: bool,
    dump_manual_finish: bool,
    timeout: u64,

    clock_flip_time: u64,

    shadow_mem: ShadowMem,

    axi_write_done_fifo: VecDeque<AxiWritePayload>,
    axi_write_fifo: VecDeque<AxiWritePayload>,
    axi_read_fifo: VecDeque<AxiWritePayload>,
}

#[cfg(feature = "trace")]
fn parse_range(input: &str) -> (u64, u64) {
    if input.is_empty() {
        return (0, 0);
    }

    let parts: Vec<&str> = input.split(",").collect();

    if parts.len() != 1 && parts.len() != 2 {
        error!("invalid dump wave range: `{input}` was given");
        return (0, 0);
    }

    const INVALID_NUMBER: &str = "invalid number";

    if parts.len() == 1 {
        return (parts[0].parse().expect(INVALID_NUMBER), 0);
    }

    if parts[0].is_empty() {
        return (0, parts[1].parse().expect(INVALID_NUMBER));
    }

    let start = parts[0].parse().expect(INVALID_NUMBER);
    let end = parts[1].parse().expect(INVALID_NUMBER);
    if start > end {
        panic!("dump start is larger than end: `{input}`");
    }

    (start, end)
}

impl Driver {
    fn get_tick(&self) -> u64 {
        get_time() / self.clock_flip_time
    }

    pub(crate) fn new(scope: SvScope, args: &OfflineArgs) -> Self {
        #[cfg(feature = "trace")]
        let (dump_start, dump_end) = parse_range(&args.dump_range);
        Self {
            scope,

            #[cfg(feature = "trace")]
            wave_path: args.wave_path.to_owned(),
            #[cfg(feature = "trace")]
            dump_start,
            #[cfg(feature = "trace")]
            dump_end,
            #[cfg(feature = "trace")]
            dump_started: false,
            dump_manual_finish: false,
            timeout: std::env::var("TIMEOUT")
                .map(|s| s.parse::<u64>().unwrap_or(u64::MAX))
                .unwrap_or(u64::MAX),
            clock_flip_time: env!("CLOCK_FLIP_TIME").parse().unwrap(),
            shadow_mem: ShadowMem::new(),
            axi_read_fifo: VecDeque::new(),
            axi_write_done_fifo: VecDeque::new(),
            axi_write_fifo: VecDeque::new(),
        }
    }

    pub(crate) fn init(&mut self) {
        #[cfg(feature = "trace")]
        if self.dump_start == 0 {
            self.start_dump_wave();
            self.dump_started = true;
        }
    }

    pub(crate) fn watchdog(&mut self) -> u8 {
        const WATCHDOG_CONTINUE: u8 = 0;
        const WATCHDOG_TIMEOUT: u8 = 1;
        const WATCHDOG_FINISH: u8 = 2;

        let tick = self.get_tick();

        if self.dump_manual_finish {
            info!("[{tick}] manual finish, exiting");
            return WATCHDOG_FINISH;
        }

        #[cfg(feature = "trace")]
        if self.dump_end != 0 && tick > self.dump_end {
            info!("[{tick}] run to dump end, exiting");
            return WATCHDOG_TIMEOUT;
        }

        #[cfg(feature = "trace")]
        if !self.dump_started && tick >= self.dump_start {
            self.start_dump_wave();
            self.dump_started = true;
        }

        if tick >= self.timeout {
            info!("[{tick}] timeout triggered, exiting");
            return WATCHDOG_TIMEOUT;
        }

        trace!("[{tick}] watchdog continue");
        WATCHDOG_CONTINUE
    }

    pub(crate) fn axi_write_done(&mut self, bid: u8, bresp: u8, buser: u8) {
        info!("axi_write_done (bid={bid}, bresp={bresp}, buser={buser})");
        let payload = self.axi_write_fifo.pop_front().unwrap();
        driver_assert_eq!(
            self,
            payload.id,
            bid,
            "ID is not equal: awid = {}, bid = {}",
            payload.id,
            bid
        );
        self.axi_write_done_fifo.push_back(payload);
    }

    pub(crate) fn axi_write_ready(&mut self) -> AxiWritePayload {
        trace!("axi_write_ready");
        let payload = AxiWritePayload::random();
        self.axi_write_fifo.push_back(payload.clone());
        self.shadow_mem.write_mem_axi(payload.clone());
        payload
    }

    pub(crate) fn axi_read_ready(&mut self) -> AxiReadPayload {
        trace!("axi_read_ready");
        if self.axi_write_done_fifo.is_empty() || !self.axi_read_fifo.is_empty() {
            let mut payload = AxiReadPayload::random();
            payload.valid = 0;
            payload
        } else {
            let write_payload = self.axi_write_done_fifo.pop_front().unwrap();
            let payload = AxiReadPayload::from_write_payload(&write_payload);
            self.axi_read_fifo.push_back(write_payload);
            info!(
                "reading({:#02x}) <- {:#08x}/{:#} with len = {:#02x}",
                payload.id,
                payload.addr,
                match payload.burst {
                    0 => "FIX",
                    1 => "INCR",
                    2 => "WARP",
                    _ => "UNKNOWN",
                },
                payload.len,
            );
            payload
        }
    }

    pub(crate) fn axi_read_done(
        &mut self,
        rdata: Vec<u32>,
        len: u8,
        rid: u8,
        rlast: u8,
        rresp: u8,
        ruser: u8,
    ) {
        info!(
            "axi_read_done (rid={rid:#02x}, rlast={rlast:#x}, \
    rresp={rresp:#08x}, ruser={ruser:#08x})"
        );
        let payload = self.axi_read_fifo.pop_front().unwrap();
        driver_assert_eq!(self, rlast, 1, "rlast is not assert");
        driver_assert_eq!(
            self,
            rid,
            payload.id,
            "id is not equal, current: {}, correct: {}",
            rid,
            payload.id
        );
        driver_assert_eq!(
            self,
            len,
            payload.len + 1,
            "len is not equal, current: {}, correct: {}",
            len,
            payload.len + 1
        );
        let compare = payload.data[..(payload.len + 1) as usize]
            .to_vec()
            .to_bytes();
        let rdata_bytes = rdata[..len as usize].to_vec().to_bytes();
        driver_assert_eq!(
            self,
            rdata_bytes,
            compare,
            "compare failed:\n\tcurrent: {}\n\tcorrect: {}",
            hex::encode(&rdata_bytes),
            hex::encode(&compare)
        );
    }

    #[cfg(feature = "trace")]
    fn start_dump_wave(&mut self) {
        dump_wave(self.scope, &self.wave_path);
    }
}
