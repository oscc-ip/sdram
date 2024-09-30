use common::MEM_SIZE;
use svdpi::{get_time, SvScope};
use tracing::{error, info, trace};

use crate::dpi::*;
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

        assert!(
            transfer_count == payload.data.len()
                && transfer_count == payload.strb.len(),
            "malformed payload: transfer_count = {:?}, payload.data.len = {:?}, payload.strb.len = {:?}",
            transfer_count, payload.data.len(), payload.strb.len(),
        );

        let bytes_number: u32 = 1 << payload.size;

        let mut lower_boundary = 0;
        let mut upper_boundary = 0;
        if payload.burst == 2 {
            lower_boundary = payload.addr / (bytes_number * transfer_count as u32)
                * (bytes_number * transfer_count as u32);
            upper_boundary = lower_boundary + bytes_number * transfer_count as u32;
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

        for item_idx in 0..transfer_count {
            if payload.strb[item_idx] == 0 {
                continue;
            }

            assert_eq!(
                payload.strb[item_idx].count_ones(),
                bytes_number,
                "the number of will write bytes is not equal"
            );

            let mut write_count = 0;

            for byte_idx in 0..AXI_SIZE / 8 {
                let byte_mask: bool = (payload.strb[item_idx] >> byte_idx) & 1 != 0;
                if byte_mask {
                    self.mem[(current_addr + write_count) as usize] =
                        (payload.data[byte_idx as usize] >> (byte_idx * 8) & 0xff) as u8;
                    write_count += 1;
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

    pub(crate) dlen: u32,

    timeout: u64,

    clock_flip_time: u64,

    shadow_mem: ShadowMem,

    axi_write_done_fifo: VecDeque<AxiWritePayload>,

    axi_write_fifo: VecDeque<AxiWritePayload>,

    axi_read_fifo: VecDeque<AxiReadPayload>,

    axi_read_buffer: Vec<u8>,
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

    const INVALID_NUMBER: &'static str = "invalid number";

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

        let self_ = Self {
            scope,

            #[cfg(feature = "trace")]
            wave_path: args.wave_path.to_owned(),
            #[cfg(feature = "trace")]
            dump_start,
            #[cfg(feature = "trace")]
            dump_end,
            #[cfg(feature = "trace")]
            dump_started: false,
            dlen: args.common_args.dlen,
            timeout: env!("TIMEOUT").parse().unwrap(),
            clock_flip_time: env!("CLOCK_FLIP_TIME").parse().unwrap(),
            shadow_mem: ShadowMem::new(),
            axi_read_fifo: VecDeque::new(),
            axi_write_done_fifo: VecDeque::new(),
            axi_write_fifo: VecDeque::new(),
            axi_read_buffer: Vec::new(),
        };

        self_
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
        #[cfg(feature = "trace")]
        if self.dump_end != 0 && tick > self.dump_end {
            info!("[{tick}] run to dump end, exiting");
            return WATCHDOG_FINISH;
        }

        #[cfg(feature = "trace")]
        if !self.dump_started && tick >= self.dump_start {
            self.start_dump_wave();
            self.dump_started = true;
        }
        trace!("[{tick}] watchdog continue");
        WATCHDOG_CONTINUE
    }

    pub(crate) fn axi_read_resp(&mut self, rdata: u32, rid: u8, rlast: u8, rresp: u8, ruser: u8) {
        trace!(
            "axi_read_resp (rdata={rdata}, rid={rid}, rlast={rlast:#x}, \
    rresp={rresp}, ruser={ruser})"
        );
        self.axi_read_buffer.extend_from_slice(&rdata.to_le_bytes());
        if rlast == 1 {
            let payload = self.axi_read_fifo.pop_front().unwrap();
            let compare = self.shadow_mem.read_mem_axi(payload);
            assert_eq!(
                compare, self.axi_read_buffer,
                "compare failed: {:?} -> {:?}",
                self.axi_read_buffer, compare
            );
            self.axi_read_buffer.clear();
        }
    }

    pub(crate) fn axi_write_done(&mut self, bid: u8, bresp: u8, buser: u8) {
        trace!("axi_write_done (bid={bid}, bresp={bresp}, buser={buser})");
        let payload = self.axi_write_fifo.pop_front().unwrap();
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
        if self.axi_write_done_fifo.is_empty() {
            let mut payload = AxiReadPayload::random();
            payload.valid = false;
            payload
        } else {
            let payload =
                AxiReadPayload::from_write_payload(self.axi_write_done_fifo.pop_front().unwrap());
            self.axi_read_fifo.push_back(payload.clone());
            payload
        }
    }

    #[cfg(feature = "trace")]
    fn start_dump_wave(&mut self) {
        dump_wave(self.scope, &self.wave_path);
    }
}
