// SPDX-FileCopyrightText: 2024 Beijing Institute of Open Source Chip
package oscc.sdramcontroller

import chisel3._
import chisel3.ltl.AssertProperty
import chisel3.util.circt.dpi.{
  RawClockedVoidFunctionCall,
  RawUnclockedNonVoidFunctionCall,
  RawClockedNonVoidFunctionCall
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
  val dataValid = UInt(8.W)
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
  val valid = UInt(8.W)
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
        val writeEnable = Bool()
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
      val doIssueAWPayload = RegInit(false.B)
      when(awFifo(awWPtr).payload.dataValid === 0.U && !awFifo(awWPtr).addrValid && !io.reset.asBool) {
        val payload_wire = WireInit(0.U.asTypeOf(new WritePayload(
          parameter.writePayloadSize,
            parameter.axiParameter.idWidth,
            parameter.axiParameter.addrWidth,
            parameter.axiParameter.dataWidth,
            parameter.axiParameter.awUserWidth,
            parameter.axiParameter.wUserWidth
        )))
        payload_wire := RawClockedNonVoidFunctionCall(
          s"axi_write_ready_${parameter.name}",
          new WritePayload(
            parameter.writePayloadSize,
            parameter.axiParameter.idWidth,
            parameter.axiParameter.addrWidth,
            parameter.axiParameter.dataWidth,
            parameter.axiParameter.awUserWidth,
            parameter.axiParameter.wUserWidth
          )
        )(io.clock, when.cond && !io.gateWrite)
        when(doIssueAWPayload && payload_wire.dataValid === 1.U) {
          awFifo(awWPtr).payload := payload_wire
          awFifo(awWPtr).index := 0.U
          awFifo(awWPtr).addrValid := true.B
          awFifo(awRPtr).writeEnable := false.B
          awWPtr := awWPtr + 1.U
        }.elsewhen(!doIssueAWPayload) {
          doIssueAWPayload := true.B
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
        awFifo(awRPtr).writeEnable := true.B
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
      channel.WLAST := awFifo(wRPtr).index >= awFifo(
        wRPtr
      ).payload.len
      channel.WVALID := awFifo(wRPtr).payload.dataValid =/= 0.U && awFifo(wRPtr).writeEnable
      when(wFire) {
        when(channel.WLAST) {
          awFifo(wRPtr).payload.dataValid := 0.U
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
      val doIssueARPayload = RegInit(false.B)

      // AR
      when(arFifo(arWPtr).payload.valid === 0.U && !io.reset.asBool) {
        val payload_wire = WireInit(0.U.asTypeOf(new ReadAddressPayload(
            parameter.axiParameter.addrWidth,
            parameter.axiParameter.idWidth,
            parameter.axiParameter.arUserWidth
        )))
        payload_wire := RawClockedNonVoidFunctionCall(
          s"axi_read_ready_${parameter.name}",
          new ReadAddressPayload(
            parameter.axiParameter.addrWidth,
            parameter.axiParameter.idWidth,
            parameter.axiParameter.arUserWidth
          )
        )(
          io.clock, when.cond && !io.gateRead
        )
        when(doIssueARPayload && payload_wire.valid === 1.U) {
          arFifo(arWPtr).payload := payload_wire
          arWPtr := arWPtr + 1.U
        }.elsewhen(!doIssueARPayload) {
          doIssueARPayload := true.B
        }
      }
      val arFire = channel.ARREADY && channel.ARVALID
      when(arFire) {
        arFifo(arRPtr).payload.valid := false.B
        arRPtr := arRPtr + 1.U
        arCount := arCount + 1.U
      }
      channel.ARVALID := arFifo(arRPtr).payload.valid
      channel.ARADDR := arFifo(arRPtr).payload.addr
      channel.ARBURST := arFifo(arRPtr).payload.burst
      channel.ARCACHE := arFifo(arRPtr).payload.cache
      channel.ARID := arFifo(arRPtr).payload.id
      channel.ARLEN := arFifo(arRPtr).payload.len
      channel.ARLOCK := arFifo(arRPtr).payload.lock
      channel.ARPROT := arFifo(arRPtr).payload.prot
      channel.ARQOS := arFifo(arRPtr).payload.qos
      channel.ARREGION := arFifo(arRPtr).payload.region
      channel.ARSIZE := arFifo(arRPtr).payload.size
      channel.ARUSER := arFifo(arRPtr).payload.user

      // R
      channel.RREADY := true.B
      val rCount = RegInit(0.U(32.W))
      val rFire = channel.RREADY && channel.RVALID
      val rdataFifo = RegInit(VecInit(Seq.fill(parameter.readPayloadSize)(0.U(32.W))))
      val wIndex = RegInit(0.U(32.W))
      when(rFire) {
        when(channel.RLAST) {
          rCount := rCount + 1.U
          wIndex := 0.U
          RawClockedVoidFunctionCall(
            s"axi_read_done_${parameter.name}"
          )(
            io.clock,
            when.cond && !io.gateRead,
            rdataFifo.asTypeOf(UInt((32 * parameter.outstanding).W)),
            channel.RID.asTypeOf(UInt(8.W)),
            channel.RLAST.asTypeOf(UInt(8.W)),
            channel.RRESP.asTypeOf(UInt(8.W)),
            channel.RUSER.asTypeOf(UInt(8.W))
          )
        }.otherwise {
          rdataFifo(wIndex) := channel.RDATA
          wIndex := wIndex + 1.U
        }
      }
      AssertProperty(BoolSequence(arCount >= rCount))
    }
  }
}
