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
  class FIFO(WIDTH: Int, DEPTH: Int, ADDR_W: Int) extends Module {
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
    val req_hole_wr_q = RegInit(UInt(1.W))

    /** When SDRAM read/write request is enable and cannot accept data, assert
      * corresponding hold status, otherwise deassert.
      */
    when (ram_rd === 1.U && ram_accept === 0.U) {
      req_hold_rd_q := 1.U
    }.elsewhen (ram_accept === 1.U) {
      req_hold_rd_q := 0.U
    }
    when (ram_wr =/= 0.U && ram_accept === 0.U) {
      req_hole_wr_q := 1.U
    }.elsewhen (ram_accept === 1.U) {
      req_hole_wr_q := 1.U
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

    when (axi.ar.valid && axi.ar.ready) {
      req_in_r := Cat(1.U, (axi.ar.bits.len === 0.U), axi.ar.bits.id)
    }

    // Response buffering
  }
}
