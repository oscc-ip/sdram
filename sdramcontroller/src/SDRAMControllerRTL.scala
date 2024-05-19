// TODO: change package to oscc
package oscc.sdramcontroller

import chisel3._
import chisel3.util.{MuxLookup, Cat}
import org.chipsalliance.amba.axi4.bundle.`enum`.burst.{FIXED, INCR, WARP}

// This is what RTL designer need to implement, as well as necessary verification signal definitions.
trait SDRAMControllerRTL extends HasSDRAMControllerInterface {

  // TODO: use Mux1H for selection
  /** Calculate the next address of AXI4 bus. */
  def calculateAddressNext(addr: UInt, axType: UInt, axLen: UInt): UInt =
    MuxLookup(axType, addr + 4.U)(
      Seq(
        FIXED -> 0.U,
        WARP -> {
          val mask = MuxLookup(axLen, "0xh3f".U(32.W))(
            Seq(
              "0d0".U -> "0h03".U,
              "0d1".U -> "0h07".U,
              "0d3".U -> "0h0F".U,
              "0d7".U -> "0h1F".U,
              "0d15".U -> "0h3F".U
            )
          )
          (addr & (~mask).asUInt) | ((addr + 4.U) & mask)
        },
        INCR -> (addr + 4.U)
      )
    )

  /** First In First Out module */
  class FIFO(WIDTH: Int = 8, DEPTH: Int = 4, ADDR_W: Int = 2) extends Module {
    val io = IO(new Bundle {
      /** FIFO clock */
      val clk_i = Input(Clock())
      /** FIFO reset */
      val rst_i = Input(Bool())
      /** FIFO data input */
      val data_in_i = Input(UInt(WIDTH.W))
      /** FIFO data push request */
      val push_i = Input(UInt(1.W))
      /** FIFO data pop request */
      val pop_i  = Input(UInt(1.W))
      /** FIFO data output */
      val data_out_o = Output(UInt(WIDTH.W))
      /** FIFO accept signal, if it's true, FIFO can input data */
      val accept_o = Output(UInt(1.W))
      /** FIFO valid signal, if it's true, FIFO can output data */
      val valid_o = Output(UInt(1.W))
    })

    /** FIFO count */
    val COUNT_W = ADDR_W + 1

    withClockAndReset(io.clk_i, io.rst_i) {
      /** FIFO buffer */
      val ram = Vec(DEPTH, Reg(UInt(WIDTH.W)))
      /** FIFO read pointer */
      val rd_ptr = RegInit(UInt(ADDR_W.W))
      /** FIFO write pointer */
      val wr_ptr = RegInit(UInt(ADDR_W.W))
      /** FIFO counter */
      val count = RegInit(UInt(COUNT_W.W))

      /** If read/write signals handshake, the corresponding pointer++, for
       * write operation, save input data to RAM pointed to by write pointer.
       */
      when ((io.push_i & io.accept_o) === 1.U) {
        ram(wr_ptr) := io.data_in_i
        wr_ptr := wr_ptr + 1.U
      }
      when ((io.pop_i & io.valid_o) === 1.U) {
        rd_ptr := rd_ptr + 1.U
      }

      /** Counter represent the status of read/write, if read signals handshake,
       * counter++, if write signals handshake, counter--
       */
      when (((io.push_i & io.accept_o) &
        (~(io.pop_i & io.valid_o)).asUInt) === 1.U) {
        count := count + 1.U
      }.elsewhen (((~(io.push_i & io.accept_o)).asUInt &
        (io.pop_i & io.valid_o)) === 1.U) {
        count := count - 1.U
      }

      /** Use counter to control whether to input or output data. Read operation
       *  is combinatorial, data only depends on the read pointer . */
      io.accept_o   := (count =/= UInt(DEPTH.W))
      io.valid_o    := (count =/= 0.U)
      io.data_out_o := ram(rd_ptr)
    }
  }

  // define registers
  withClockAndReset(clock, reset) {
    /** SDRAM read/write request length */
    val req_len_q = RegInit(UInt(8.W))
    /** SDRAM read/write addr */
    val req_addr_q = RegInit(UInt(32.W))
    /** SDRAM write request enable */
    val req_wr_q = RegInit(UInt(1.W))
    /** SDRAM read request enable */
    val req_rd_q = RegInit(UInt(1.W))
    /** SDRAM read/write request id */
    val req_id_q = RegInit(UInt(4.W))
    /** SDRAM read/write burst type */
    val req_axburst_q = RegInit(UInt(2.W))
    /** SDRAM read/write burst length */
    val req_axlen_q = RegInit(UInt(8.W))
    /** SDRAM read/write priority */
    val req_prio_q = RegInit(UInt(1.W))

    /** SDRAM write strb, it cotains both enable and mask functions. when it
      * don't equal 4'b0000, it represent write is enable.
      */
    val ram_wr = WireInit(UInt(4.W))
    /** SDRAM read enalbe */
    val ram_rd = WireInit(UInt(4.W))
    /** Whether SDRAM can accept data */
    val ram_accept = WireInit(UInt(1.W))

    /** When SDRAM mode is brust, let it perform read or write operation
      * continuously before request ends.
      */
    when ((ram_wr =/= 0.U || ram_rd === 1.U) && ram_accept === 1.U) {
      when (req_len_q === 0.U) {
        req_rd_q := 0.U
        req_wr_q := 0.U
      }
      req_addr_q := calculateAddressNext(req_addr_q, req_axburst_q, req_axlen_q)
      req_len_q := req_len_q - 1.U
    }

    /** When read/write handshake happens, update related request registers. */
    when (axi.aw.valid && axi.aw.ready) {
      when (axi.w.valid && axi.w.ready) {
        req_wr_q      := !axi.w.bits.last
        req_len_q     := axi.aw.bits.len - 1.U
        req_id_q      := axi.aw.bits.id
        req_axburst_q := axi.aw.bits.burst
        req_axlen_q   := axi.aw.bits.len
        req_addr_q    := calculateAddressNext(axi.aw.bits.addr,
                                              axi.aw.bits.burst,
                                              axi.aw.bits.len)
      }.otherwise {
        req_wr_q      := 1.U
        req_len_q     := axi.aw.bits.len
        req_id_q      := axi.aw.bits.id
        req_axburst_q := axi.aw.bits.burst
        req_axlen_q   := axi.aw.bits.len
        req_addr_q    := axi.aw.bits.addr
      }
      req_prio_q := !req_prio_q
    }.elsewhen(axi.ar.valid && axi.ar.ready) {
      req_rd_q      := (axi.ar.bits.len =/= 0.U)
      req_len_q     := axi.ar.bits.len - 1.U
      req_addr_q    := calculateAddressNext(axi.ar.bits.addr,
                                            axi.ar.bits.burst,
                                            axi.ar.bits.len)
      req_id_q      := axi.ar.bits.id
      req_axburst_q := axi.ar.bits.burst
      req_axlen_q   := axi.ar.bits.len
      req_prio_q    := !req_prio_q
    }

    /** SDRAM read request hold status */
    val req_hold_rd_q = RegInit(UInt(1.W))
    /** SDRAM write request hold status */
    val req_hold_wr_q = RegInit(UInt(1.W))

    /** When SDRAM read/write request is enable and cannot accept data, assert
      * corresponding hold status, otherwise deassert.
      */
    when (ram_rd === 1.U && ram_accept === 0.U) {
      req_hold_rd_q := 1.U
    }.elsewhen (ram_accept === 1.U) {
      req_hold_rd_q := 0.U
    }
    when (ram_wr =/= 0.U && ram_accept === 0.U) {
      req_hold_wr_q := 1.U
    }.elsewhen (ram_accept === 1.U) {
      req_hold_wr_q := 1.U
    }

    // Request tracking
    /**  */
    val req_push_w = ((ram_rd === 1.U) || (ram_wr =/= 0.U)) && (ram_accept === 1.U)
    /**  */
    val req_in_r = RegInit(UInt(6.W))
    /**  */
    val req_out_valid_w = WireInit(UInt(1.W))
    /**  */
    val req_out_w = WireInit(UInt(6.W))
    /**  */
    val resp_accept_w = WireInit(UInt(1.W))
    /**  */
    val req_fifo_accept_w = WireInit(UInt(1.W))

    when (axi.ar.valid && axi.ar.ready) {
      req_in_r := Cat(1.U(1.W), (axi.ar.bits.len === 0.U), axi.ar.bits.id)
    }.elsewhen (axi.aw.valid && axi.aw.ready) {
      req_in_r := Cat(0.U(1.W), (axi.aw.bits.len === 0.U), axi.aw.bits.id)
    }.otherwise {
      req_in_r := Cat(ram_rd, (req_len_q === 0.U), req_id_q)
    }

    val u_requests = Module(new FIFO(6))
    u_requests.io.clk_i      := clock
    u_requests.io.rst_i      := reset
    u_requests.io.data_in_i  := req_in_r
    u_requests.io.push_i     := req_push_w
    u_requests.io.accept_o   := req_fifo_accept_w
    u_requests.io.pop_i      := resp_accept_w
    u_requests.io.data_out_o := req_out_w
    u_requests.io.valid_o    := req_out_valid_w

    val resp_is_write_w = Mux(req_out_valid_w === 1.U, ~req_out_w(5), 0.U(1.W))
    val resp_is_read_w  = Mux(req_out_valid_w === 1.U,  req_out_w(5), 0.U(1.W))
    val resp_is_last_w  = req_out_w(4)
    val resp_id_w       = req_out_w(3, 0)

    // Response buffering
    val resp_valid_w = WireInit(UInt(1.W))

    val u_response = Module(new FIFO(32))
    u_response.io.clk_i      := clock
    u_response.io.rst_i      := reset
    u_response.io.data_in_i  := ram_read_data_i
    u_response.io.push_i     := ram_ack_i
    u_response.io.accept_o   := DontCare
    u_response.io.pop_i      := resp_accept_w
    u_response.io.data_out_o := axi.r.bits.data
    u_response.io.valid_o    := resp_valid_w

    // SDRAM Request
    val write_prio_w = ((req_prio_q  & !req_hold_rd_q) | req_hold_wr_q)
    val read_prio_w  = ((!req_prio_q & !req_hold_wr_q) | req_hold_rd_q)

    val write_active_w = (axi.aw.valid || (req_wr_q === 1.U)) &&
                         !req_rd_q &&
                         (req_fifo_accept_w === 1.U) &&
                         (write_prio_w === 1.U || req_wr_q === 1.U || !axi.ar.valid)
    val read_active_w  = (axi.ar.valid || (req_rd_q === 1.U)) &&
                         !req_wr_q &&
                         (req_fifo_accept_w === 1.U) &&
                         (read_prio_w === 1.U || req_rd_q === 1.U || !axi.aw.valid)

    axi.aw.ready := write_active_w && !req_wr_q && (ram_accept_i === 1.U) &&
                    req_fifo_accept_w
    axi.w.ready  := write_active_w &&              (ram_accept_i === 1.U) &&
                    req_fifo_accept_w;
    axi.ar.ready := read_active_w  && !req_rd_q && (ram_accept_i === 1.U) &&
                    req_fifo_accept_w

    val addr_w = (Mux((req_wr_q === 1.U || req_rd_q === 1.U),
                  req_addr_q,
                  Mux(write_active_w, axi.aw.bits.addr, axi.ar.bits.addr)))

    val wr_w = write_active_w && axi.w.valid
    val rd_w = read_active_w

    val ram_addr_o = addr_w
    val ram_write_data_o = axi.w.bits.data
    val ram_rd_o  = rd_w
    val ram_wr_o  = Mux(wr_w, axi.w.bits.strb, 0.U((4.W)))
    val ram_len_o = Mux(axi.aw.valid, axi.aw.bits.len,
                    Mux(axi.ar.valid, axi.ar.bits.len, 0.U(8.W)))

    // SDRAM Response
    axi.b.valid     := resp_valid_w & resp_is_write_w.asUInt & resp_is_last_w
    axi.b.bits.resp := 0.U(2.W)
    axi.b.bits.id   := resp_id_w

    axi.r.valid     := resp_valid_w & resp_is_read_w
    axi.r.bits.resp := 0.U(2.W)
    axi.r.bits.id   := resp_id_w
    axi.r.bits.last := resp_is_last_w

    resp_accept_w := (axi.r.valid & axi.r.ready) |
                     (axi.b.valid & axi.b.ready) |
                     (resp_valid_w & resp_is_write_w.asUInt & !resp_is_last_w)
  }
}
