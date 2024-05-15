// TODO: change package to oscc
package oscc.sdramcontroller

import chisel3._
import chisel3.util.MuxLookup
import org.chipsalliance.amba.axi4.bundle.`enum`.burst.{FIXED, INCR, WARP}

// This is what RTL designer need to implement, as well as necessary verification signal definitions.
trait SDRAMControllerRTL extends HasSDRAMControllerInterface {

  // TODO: use Mux1H for selection
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
          (addr & ~mask) | ((addr + 4.U) & mask)
        },
        INCR -> (addr + 4.U)
      )
    )

  // define registers
  withClockAndReset(clock, reset) {
    val req_len_q = RegInit(UInt(8.W))
    val req_addr_q = RegInit(UInt(32.W))
    val req_wr_q = RegInit(UInt(1.W))
    val req_rd_q = RegInit(UInt(1.W))
    val req_id_q = RegInit(UInt(4.W))
    val req_axburst_q = RegInit(UInt(2.W))
    val req_axlen_q = RegInit(UInt(8.W))
    val req_prio_q = RegInit(UInt(1.W))

    when(req_len_q===0.U){
      req_rd_q := 0.U
      req_wr_q := 0.U
    }
    req_addr_q := calculateAddressNext(req_addr_q, req_axburst_q, req_axlen_q)
    req_len_q := req_len_q - 1.U
  }
}