// SPDX-FileCopyrightText: 2024 Beijing Institute of Open Source Chip
package oscc.sdramcontroller

import chisel3._
import chisel3.ltl.AssertProperty
import chisel3.util.circt.dpi.{
  RawClockedVoidFunctionCall,
  RawUnclockedNonVoidFunctionCall
}
import chisel3.util.{isPow2, log2Ceil}
import org.chipsalliance.amba.axi4.bundle._
import chisel3.ltl.Sequence._

case class AXI4MasterAgentParameter(
    name: String,
    axiParameter: AXI4BundleParameter,
    outstanding: Int,
    readPayloadSize: Int,
    writePayloadSize: Int
)

class AXI4MasterAgentInterface(parameter: AXI4MasterAgentParameter)
    extends Bundle {
  val clock: Clock = Input(Clock())
  val reset: Reset = Input(Reset())
  val channelId: UInt = Input(Const(UInt(64.W)))
  // don't issue read DPI
  val gateRead: Bool = Input(Bool())
  // don't issue write DPI
  val gateWrite: Bool = Input(Bool())
  val channel = org.chipsalliance.amba.axi4.bundle.verilog
    .irrevocable(parameter.axiParameter)
}

class WritePayload(
    length: Int,
    idWidth: Int,
    addrWidth: Int,
    dataWidth: Int,
    awUserWidth: Int,
    wUserWidth: Int
) extends Bundle {
  val id = UInt(math.max(8, idWidth).W)
  val len = UInt(8.W)
  val addr = UInt(addrWidth.W)
  val data = Vec(length, UInt(dataWidth.W))
  // For dataWidth <= 8, align strb to u8 for a simple C-API
  val strb = Vec(length, UInt(math.max(8, dataWidth / 8).W))
  val wUser = Vec(length, UInt(math.max(8, wUserWidth).W))
  val awUser = UInt(math.max(8, awUserWidth).W)
  val dataValid = Bool()
  val burst = UInt(8.W)
  val cache = UInt(8.W)
  val lock = UInt(8.W)
  val prot = UInt(8.W)
  val qos = UInt(8.W)
  val region = UInt(8.W)
  val size = UInt(8.W)
}

class ReadAddressPayload(addrWidth: Int, idWidth: Int, userWidth: Int)
    extends Bundle {
  val addr = UInt(addrWidth.W)
  val id = UInt(math.max(8, idWidth).W)
  val user = UInt(math.max(8, userWidth).W)
  val burst = UInt(8.W)
  val cache = UInt(8.W)
  val len = UInt(8.W)
  val lock = UInt(8.W)
  val prot = UInt(8.W)
  val qos = UInt(8.W)
  val region = UInt(8.W)
  val size = UInt(8.W)
  val valid = Bool()
}

// consume transaction from DPI, drive RTL signal
class AXI4MasterAgent(parameter: AXI4MasterAgentParameter)
    extends FixedIORawModule[AXI4MasterAgentInterface](
      new AXI4MasterAgentInterface(parameter)
    ) {
  dontTouch(io)
  io.channel match {
    case channel: AXI4RWIrrevocableVerilog =>
      new WriteManager(channel)
      new ReadManager(channel)
    case channel: AXI4ROIrrevocableVerilog =>
      new ReadManager(channel)
    case channel: AXI4WOIrrevocableVerilog =>
      new WriteManager(channel)
  }

  private class WriteManager(
      channel: AWChannel
        with AWFlowControl
        with WChannel
        with WFlowControl
        with BChannel
        with BFlowControl
  ) {
    withClockAndReset(io.clock, io.reset) {
      class AWValueType extends Bundle {
        val payload = new WritePayload(
          parameter.writePayloadSize,
          parameter.axiParameter.idWidth,
          parameter.axiParameter.addrWidth,
          parameter.axiParameter.dataWidth,
          parameter.axiParameter.awUserWidth,
          parameter.axiParameter.wUserWidth
        )
        val index = UInt(log2Ceil(parameter.writePayloadSize).W)
        val addrValid = Bool()
      }

      val awFifo =
        RegInit(0.U.asTypeOf(Vec(parameter.outstanding, new AWValueType)))
      require(isPow2(parameter.outstanding), "Need to handle pointers")
      val awWPtr =
        RegInit(0.U.asTypeOf(UInt(log2Ceil(parameter.outstanding).W)))
      val awRPtr =
        RegInit(0.U.asTypeOf(UInt(log2Ceil(parameter.outstanding).W)))
      val wRPtr = RegInit(0.U.asTypeOf(UInt(log2Ceil(parameter.outstanding).W)))
      val awCount = RegInit(0.U(32.W))
      // AW
      when(channel.AWREADY && !awFifo(awWPtr).payload.dataValid) {
        awFifo(awWPtr).payload := RawUnclockedNonVoidFunctionCall(
          s"axi_write_ready_${parameter.name}",
          new WritePayload(
            parameter.writePayloadSize,
            parameter.axiParameter.idWidth,
            parameter.axiParameter.addrWidth,
            parameter.axiParameter.dataWidth,
            parameter.axiParameter.awUserWidth,
            parameter.axiParameter.wUserWidth
          )
        )(when.cond && !io.gateWrite)
        awFifo(awWPtr).index := 0.U
        when(awFifo(awWPtr).payload.dataValid) {
          awFifo(awWPtr).addrValid := true.B
          awWPtr := awWPtr + 1.U
        }
      }
      channel.AWADDR := awFifo(awRPtr).payload.addr
      channel.AWVALID := awFifo(awRPtr).addrValid
      channel.AWSIZE := awFifo(awRPtr).payload.size
      channel.AWBURST := awFifo(awRPtr).payload.burst
      channel.AWLOCK := awFifo(awRPtr).payload.lock
      channel.AWCACHE := awFifo(awRPtr).payload.cache
      channel.AWPROT := awFifo(awRPtr).payload.prot
      channel.AWQOS := awFifo(awRPtr).payload.qos
      channel.AWREGION := awFifo(awRPtr).payload.region
      channel.AWID := awFifo(awRPtr).payload.id
      channel.AWLEN := awFifo(awRPtr).payload.len
      channel.AWUSER := awFifo(awRPtr).payload.awUser
      val awFire = channel.AWREADY && channel.AWVALID
      when(awFire) {
        awFifo(awRPtr).addrValid := false.B
        awRPtr := awRPtr + 1.U
        awCount := awCount + 1.U
      }

      // W
      val wFire = channel.WREADY && channel.WVALID
      val wCount = RegInit(0.U(32.W))
      channel.WDATA := awFifo(wRPtr).payload.data(
        awFifo(wRPtr).index
      )
      channel.WSTRB := awFifo(wRPtr).payload.strb(
        awFifo(wRPtr).index
      )
      channel.WUSER := awFifo(wRPtr).payload.wUser(
        awFifo(wRPtr).index
      )
      channel.WLAST := awFifo(wRPtr).index + 1.U >= awFifo(
        wRPtr
      ).payload.len
      channel.WVALID := awFifo(wRPtr).payload.dataValid
      when(wFire) {
        when(channel.WLAST) {
          awFifo(wRPtr).payload.dataValid := false.B
          wRPtr := wRPtr + 1.U
          wCount := wCount + 1.U
        }.otherwise(
          awFifo(wRPtr).index := awFifo(
            wRPtr
          ).index + 1.U
        )
      }

      // B
      channel.BREADY := true.B // note: keep it simple and stupid, handle corner cases in Rust
      val bFire = channel.BREADY && channel.BVALID
      when(bFire) {
        RawClockedVoidFunctionCall(s"axi_write_done_${parameter.name}")(
          io.clock,
          when.cond && !io.gateWrite,
          channel.BID.asTypeOf(UInt(8.W)),
          channel.BRESP.asTypeOf(UInt(8.W)),
          channel.BUSER.asTypeOf(UInt(8.W))
        )
      }

      AssertProperty(BoolSequence(awCount >= wCount))
    }
  }

  private class ReadManager(
      channel: ARChannel with ARFlowControl with RChannel with RFlowControl
  ) {
    withClockAndReset(io.clock, io.reset) {
      class ARValueType extends Bundle {
        val payload = new ReadAddressPayload(
          parameter.axiParameter.addrWidth,
          parameter.axiParameter.idWidth,
          parameter.axiParameter.userDataWidth
        )
      }

      val arFifo: Vec[ARValueType] =
        RegInit(0.U.asTypeOf(Vec(parameter.outstanding, new ARValueType)))
      require(isPow2(parameter.outstanding), "Need to handle pointers")
      val arWPtr =
        RegInit(0.U.asTypeOf(UInt(log2Ceil(parameter.outstanding).W)))
      val arRPtr =
        RegInit(0.U.asTypeOf(UInt(log2Ceil(parameter.outstanding).W)))
      val arCount = RegInit(0.U(32.W))

      // AR
      channel.ARVALID := !arFifo(arWPtr).payload.valid
      when(channel.ARREADY) {
        arFifo(arWPtr).payload := RawUnclockedNonVoidFunctionCall(
          s"axi_read_ready_${parameter.name}",
          new ReadAddressPayload(
            parameter.axiParameter.addrWidth,
            parameter.axiParameter.idWidth,
            parameter.axiParameter.arUserWidth
          )
        )(
          when.cond && !io.gateRead
        )
        when(arFifo(arWPtr).payload.valid) {
          arFifo(arWPtr).payload.valid := false.B
          arWPtr := arWPtr + 1.U
        }
      }
      val arFire = channel.ARREADY && channel.ARVALID
      when(arFire) {
        arRPtr := arRPtr + 1.U
        arCount := arCount + 1.U
      }
      channel.ARADDR := arFifo(arWPtr).payload.addr
      channel.ARBURST := arFifo(arWPtr).payload.burst
      channel.ARCACHE := arFifo(arWPtr).payload.cache
      channel.ARID := arFifo(arWPtr).payload.id
      channel.ARLEN := arFifo(arWPtr).payload.len
      channel.ARLOCK := arFifo(arWPtr).payload.lock
      channel.ARPROT := arFifo(arWPtr).payload.prot
      channel.ARQOS := arFifo(arWPtr).payload.qos
      channel.ARREGION := arFifo(arWPtr).payload.region
      channel.ARSIZE := arFifo(arWPtr).payload.size
      channel.ARUSER := arFifo(arWPtr).payload.user

      // R
      channel.RREADY := true.B
      val rCount = RegInit(0.U(32.W))
      val rFire = channel.RREADY && channel.RVALID
      when(rFire) {
        rCount := rCount + 1.U
        RawClockedVoidFunctionCall(
          s"axi_read_resp_${parameter.name}"
        )(
          io.clock,
          when.cond && !io.gateRead,
          channel.RDATA,
          channel.RID.asTypeOf(UInt(8.W)),
          channel.RLAST.asTypeOf(UInt(8.W)),
          channel.RRESP.asTypeOf(UInt(8.W)),
          channel.RUSER.asTypeOf(UInt(8.W))
        )
      }
      AssertProperty(BoolSequence(arCount >= rCount))
    }
  }
}
