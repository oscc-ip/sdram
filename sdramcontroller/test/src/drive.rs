use common::MEM_SIZE;
use tracing::{debug, error, info, trace};

use crate::dpi::*;
use crate::svdpi::SvScope;
use crate::OfflineArgs;

struct ShadowMem {
  mem: Vec<u8>,
}

impl ShadowMem {
  pub fn new() -> Self {
    Self { mem: vec![0; MEM_SIZE] }
  }
  pub fn apply_writes(&mut self) {
    todo!();
  }

  pub fn read_mem(&self, addr: u32, size: u32) -> &[u8] {
    let start = addr as usize;
    let end = (addr + size) as usize;
    &self.mem[start..end]
  }

  // size: 1 << arsize
  // bus_size: AXI bus width in bytes
  // return: Vec<u8> with len=bus_size
  // if size < bus_size, the result is padded due to AXI narrow transfer rules
  pub fn read_mem_axi(&self, addr: u32, size: u32, bus_size: u32) -> Vec<u8> {
    assert!(
      addr % size == 0 && bus_size % size == 0,
      "unaligned access addr={addr:#x} size={size}B dlen={bus_size}B"
    );

    let data = self.read_mem(addr, size);
    if size < bus_size {
      // narrow
      let mut data_padded = vec![0; bus_size as usize];
      let start = (addr % bus_size) as usize;
      let end = start + data.len();
      data_padded[start..end].copy_from_slice(data);

      data_padded
    } else {
      // normal
      data.to_vec()
    }
  }

  // size: 1 << awsize
  // bus_size: AXI bus width in bytes
  // masks: write strokes, len=bus_size
  // data: write data, len=bus_size
  pub fn write_mem_axi(
    &mut self,
    addr: u32,
    size: u32,
    bus_size: u32,
    masks: &[bool],
    data: &[u8],
  ) {
    assert!(
      addr % size == 0 && bus_size % size == 0,
      "unaligned write access addr={addr:#x} size={size}B dlen={bus_size}B"
    );

    // handle strb=0 AXI payload
    if !masks.iter().any(|&x| x) {
      trace!("Mask 0 write detect");
      return;
    }

    // TODO: we do not check strobe is compatible with (addr, awsize)
    let addr_align = addr & ((!bus_size) + 1);

    let bus_size = bus_size as usize;
    assert_eq!(bus_size, masks.len());
    assert_eq!(bus_size, data.len());

    for i in 0..bus_size {
      if masks[i] {
        self.mem[addr_align as usize + i] = data[i];
      }
    }
  }
}

pub(crate) struct Driver {

  // SvScope from t1_cosim_init
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

  shadow_mem: ShadowMem,
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
      timeout: args.timeout,
      shadow_mem: ShadowMem::new(),
    };

    self_
  }

  pub(crate) fn axi_read_resp(&mut self,
    rdata: u32,
    rid: u8,
    rlast: u8,
    rresp: u8,
    ruser: u8
  ) {
    trace!(
      "axi_read_resp (rdata={rdata}, rid={rid}, rlast={rlast:#x}, \
    rresp={rresp}, ruser={ruser})"
    );
  }


  pub(crate) fn axi_write_done(&mut self,
    bid: u8,
    bresp: u8,
    buser: u8
  ) {
    trace!(
      "axi_write_done (bid={bid}, bresp={bresp}, buser={buser})"
    );
  }

  pub(crate) fn axi_write_ready(&mut self) -> AxiWritePayload {
    trace!(
      "axi_write_ready"
    );

    todo!();
    // AxiWritePayload { }
  }

  pub(crate) fn axi_read_ready(&mut self) -> AxiReadPayload {
    trace!(
      "axi_read_ready"
    );

    todo!();
    // AxiReadPayload { }
  }

  pub(crate) fn watchdog(&mut self) -> u8 {
    todo!();
  }

  #[cfg(feature = "trace")]
  fn start_dump_wave(&mut self) {
    dump_wave(self.scope, &self.wave_path);
  }

}
