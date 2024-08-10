package oscc.sdramcontroller

import chisel3._
import chisel3.experimental.{ExtModule, SerializableModuleGenerator}
import chisel3.util.HasExtModuleInline
import chisel3.util.circt.dpi.RawUnclockedNonVoidFunctionCall
import org.chipsalliance.amba.axi4.bundle.AXI4RWIrrevocableVerilog
import chisel3.experimental.dataview.DataViewable

class W9825G6KH extends BlackBox {
  val io = IO(new Bundle {
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
  })
}

class SDRAMControllerTestbenchMain(
                                    val path: os.Path
) extends RawModule
    with ImplicitClock
    with ImplicitReset {
  val clockGen = Module(new ExtModule with HasExtModuleInline {
    override def desiredName = "ClockGen"
    setInline(
      s"$desiredName.sv",
      s"""module $desiredName(output reg clock, output reg reset);
        |  export "DPI-C" function dump_wave;
        |  function dump_wave(input string file);
        |`ifdef VCS
        |    $$fsdbDumpfile(file);
        |    $$fsdbDumpvars("+all");
        |    $$fsdbDumpon;
        |`endif
        |`ifdef VERILATOR
        |    $$dumpfile(file);
        |    $$dumpvars(0);
        |`endif
        |  endfunction;
        |
        |  import "DPI-C" context function void cosim_init();
        |  initial begin
        |    cosim_init();
        |    clock = 1'b0;
        |    reset = 1'b1;
        |  end
        |  initial #(11) reset = 1'b0;
        |
        |  reg [31:0] cycle_count;
        |  initial cycle_count = 32'b0;
        |
        |  always @(posedge clock) begin
        |    if (cycle_count < 1_000_000_000) begin
        |      cycle_count <= cycle_count + 1;
        |    end else begin
        |      $$display("Simulation reached 1_000_000_000 cycles. Stopping.");
        |      $$stop; // Force stop the simulation
        |    end
        |  end
        |
        |  always #10 clock = ~clock;
        |endmodule
        |""".stripMargin
    )
    val clock = IO(Output(Bool()))
    val reset = IO(Output(Bool()))
  })

  val parameter = upickle.default.read[SDRAMControllerParameter](os.read(path))

  val dut = SerializableModuleGenerator[
    SDRAMController,
    SDRAMControllerParameter
  ](
    classOf[SDRAMController],
    parameter
  ).instance()

  // TODO: this initial way cannot happen before reset...
  val initFlag = RegInit(false.B)
  dut.io := DontCare
  dut.io.clock := clockGen.clock.asClock
  dut.io.reset := clockGen.reset

  val bundle = dut.io.axi.viewAs[AXI4RWIrrevocableVerilog]
  val agent = Module(
    new AXI4MasterAgent(
      AXI4MasterAgentParameter(
        name = "axi4Probe",
        axiParameter = bundle.parameter,
        outstanding = 4,
        readPayloadSize = 1,
        writePayloadSize = 1
      )
    )
  ).suggestName(s"axi4_channel_probe")
  agent.io.channel <> bundle
  agent.io.clock := clockGen.clock.asClock
  agent.io.reset := clockGen.reset
  agent.io.channelId := 0.U
  agent.io.gateRead := false.B
  agent.io.gateWrite := false.B

  when(!initFlag) {
    initFlag := true.B
  }
  val hasBeenReset = RegNext(true.B, false.B)

  /** SDRAM <-> DUT */
  Seq
    .fill(parameter.sdramParameter.csWidth) {
      Module(new W9825G6KH).io
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

  override protected def implicitClock: Clock = clockGen.clock.asClock

  override protected def implicitReset: Reset = clockGen.reset
}
