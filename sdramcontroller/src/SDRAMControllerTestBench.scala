package oscc.sdramcontroller

import chisel3._
import chisel3.experimental.hierarchy.{instantiable, public, Instance, Instantiate}
import chisel3.experimental.{SerializableModule, SerializableModuleParameter}
import chisel3.properties.{Class, Property}
import chisel3.util.{Counter, HasExtModuleInline}
import chisel3.util.circt.dpi.{RawClockedNonVoidFunctionCall, RawUnclockedNonVoidFunctionCall}
import chisel3.experimental.dataview.DataViewable

import scala.util.chaining._
import org.chipsalliance.amba.axi4.bundle.AXI4RWIrrevocableVerilog
import org.chipsalliance.amba.axi4.bundle.AXI4RWIrrevocable.viewVerilog

object SDRAMControllerTestBenchParameter {
  implicit def rwP: upickle.default.ReadWriter[SDRAMControllerTestBenchParameter] =
    upickle.default.macroRW
}

case class SDRAMControllerTestBenchParameter(
  sdramControllerParameter: SDRAMControllerParameter,
  testVerbatimParameter:    TestVerbatimParameter,
  timeout:                  Int)
    extends SerializableModuleParameter

class W9825G6KHInterface extends Bundle {
  val Dq_i = Input(UInt(32.W))
  val Dq_o = Output(UInt(32.W))
  val Addr = Input(UInt(13.W))
  val Bs = Input(UInt(2.W))
  val Clk = Input(Clock())
  val Cke = Input(Bool())
  val Cs_n = Input(Bool())
  val Ras_n = Input(Bool())
  val Cas_n = Input(Bool())
  val We_n = Input(Bool())
  val Dqm = Input(UInt(4.W))
}

@public
class W9825G6KH extends FixedIOExtModule(new W9825G6KHInterface)

class SDRAMControllerTestBench(val parameter: SDRAMControllerTestBenchParameter)
    extends RawModule
    with SerializableModule[SDRAMControllerTestBenchParameter]
    with ImplicitClock
    with ImplicitReset {
  val verbatim: Instance[TestVerbatim] = Instantiate(new TestVerbatim(parameter.testVerbatimParameter))
  val dut:      Instance[SDRAMController] = Instantiate(new SDRAMController(parameter.sdramControllerParameter))
  val agent = Instantiate(
    new AXI4MasterAgent(
      AXI4MasterAgentParameter(
        name = "axi4Probe",
        axiParameter = dut.io.axi.parameter,
        outstanding = 4,
        readPayloadSize = 1,
        writePayloadSize = 100
      )
    )
  ).tap(_.suggestName(s"axi4_channel_probe"))

  val initFlag = RegInit(false.B)
  dut.io := DontCare
  dut.io.clock := implicitClock
  dut.io.reset := implicitReset

  agent.io.channel <> dut.io.axi.viewAs[AXI4RWIrrevocableVerilog]
  agent.io.clock := implicitClock
  agent.io.reset := implicitReset
  agent.io.channelId := 0.U
  agent.io.gateRead := false.B
  agent.io.gateWrite := false.B

  when(!initFlag) {
    initFlag := true.B
  }
  val hasBeenReset = RegNext(true.B, false.B)

  // For each timeout ticks, check it
  val watchdogCode = RawClockedNonVoidFunctionCall("cosim_watchdog", UInt(8.W))(agent.io.clock, true.B)
  when(watchdogCode =/= 0.U) {
    stop(cf"""{"event":"SimulationStop","reason": ${watchdogCode}}\n""")
  }

  /** SDRAM <-> DUT */
  Seq
    .fill(parameter.sdramControllerParameter.sdramParameter.csWidth) {
      Instantiate(new W9825G6KH).io
    }
    .zipWithIndex
    .foreach { case (bundle, index) =>
      bundle.Addr := dut.io.sdram.a
      bundle.Bs := dut.io.sdram.ba
      bundle.Cke := dut.io.sdram.cke(index).asBool
      bundle.Clk := dut.io.sdram.ck(index)
      bundle.Cs_n := dut.io.sdram.cs(index).asBool
      bundle.Dq_i := dut.io.sdram.dqo
      dut.io.sdram.dqi := bundle.Dq_o
      bundle.Dqm := dut.io.sdram.dqm
      bundle.Ras_n := dut.io.sdram.ras
      bundle.We_n := dut.io.sdram.we
      bundle.Cas_n := dut.io.sdram.cas
    }

  override protected def implicitClock: Clock = verbatim.io.clock

  override protected def implicitReset: Reset = verbatim.io.reset
}

// Don't touch

object TestVerbatimParameter {
  implicit def rwP: upickle.default.ReadWriter[TestVerbatimParameter] =
    upickle.default.macroRW
}

case class TestVerbatimParameter(
  useAsyncReset:    Boolean,
  initFunctionName: String,
  dumpFunctionName: String,
  clockFlipTick:    Int,
  resetFlipTick:    Int)
    extends SerializableModuleParameter

@instantiable
class TestVerbatimOM(parameter: TestVerbatimParameter) extends Class {
  val useAsyncReset:    Property[Boolean] = IO(Output(Property[Boolean]()))
  val initFunctionName: Property[String] = IO(Output(Property[String]()))
  val dumpFunctionName: Property[String] = IO(Output(Property[String]()))
  val clockFlipTick:    Property[Int] = IO(Output(Property[Int]()))
  val resetFlipTick:    Property[Int] = IO(Output(Property[Int]()))

  useAsyncReset := Property(parameter.useAsyncReset)
  initFunctionName := Property(parameter.initFunctionName)
  dumpFunctionName := Property(parameter.dumpFunctionName)
  clockFlipTick := Property(parameter.clockFlipTick)
  resetFlipTick := Property(parameter.resetFlipTick)
}

/** Test blackbox for clockgen, wave dump and extra testbench-only codes. */
class TestVerbatimInterface(parameter: TestVerbatimParameter) extends Bundle {
  val clock: Clock = Output(Clock())
  val reset: Reset = Output(
    if (parameter.useAsyncReset) AsyncReset() else Bool()
  )
}

@instantiable
class TestVerbatim(parameter: TestVerbatimParameter)
    extends FixedIOExtModule(new TestVerbatimInterface(parameter))
    with HasExtModuleInline {
  setInline(
    s"$desiredName.sv",
    s"""module $desiredName(output reg clock, output reg reset);
       |  export "DPI-C" function ${parameter.dumpFunctionName};
       |  function ${parameter.dumpFunctionName}(input string file);
       |`ifdef VCS
       |    $$fsdbDumpfile(file);
       |    $$fsdbDumpvars("+all");
       |    $$fsdbDumpSVA;
       |    $$fsdbDumpon;
       |`endif
       |`ifdef VERILATOR
       |    $$dumpfile(file);
       |    $$dumpvars(0);
       |`endif
       |  endfunction;
       |
       |  import "DPI-C" context function void ${parameter.initFunctionName}();
       |  initial begin
       |    ${parameter.initFunctionName}();
       |    clock = 1'b0;
       |    reset = 1'b1;
       |  end
       |  initial #(${parameter.resetFlipTick}) reset = 1'b0;
       |  always #${parameter.clockFlipTick} clock = ~clock;
       |endmodule
       |""".stripMargin
  )
}
