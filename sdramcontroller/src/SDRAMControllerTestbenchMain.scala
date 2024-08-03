package oscc.sdramcontroller

import chisel3._
import chisel3.experimental.{ExtModule, SerializableModuleGenerator}
import chisel3.util.HasExtModuleInline
import chisel3.util.circt.dpi.RawUnclockedNonVoidFunctionCall

class SDRAMControllerTestbenchMain(
    val parameter: os.Path
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
         |  import "DPI-C" context function void t1_cosim_init();
         |  initial begin
         |    t1_cosim_init();
         |    clock = 1'b0;
         |    reset = 1'b1;
         |  end
         |  initial #(11) reset = 1'b0;
         |  always #10 clock = ~clock;
         |endmodule
         |""".stripMargin
    )
    val clock = IO(Output(Bool()))
    val reset = IO(Output(Bool()))
  })

  val dut = SerializableModuleGenerator[
    SDRAMController,
    SDRAMControllerParameter
  ](
    classOf[SDRAMController],
    upickle.default.read[SDRAMControllerParameter](os.read(parameter))
  ).instance()

  val simulationTime: UInt = RegInit(0.U(64.W))
  // TODO: this initial way cannot happen before reset...
  val initFlag = RegInit(false.B)
  val watchdog = RawUnclockedNonVoidFunctionCall("cosim_watchdog", UInt(8.W))(
    simulationTime(9, 0) === 0.U
  )
  simulationTime := simulationTime + 1.U
  dut.io.clock := clockGen.clock.asClock
  dut.io.reset := clockGen.reset
  dut.io := DontCare

  when(!initFlag) {
    initFlag := true.B
    printf(cf"""{"event":"SimulationStart","cycle":${simulationTime}}\n""")
  }
  val hasBeenReset = RegNext(true.B, false.B)
  when(watchdog =/= 0.U) {
    stop(
      cf"""{"event":"SimulationStop","reason": ${watchdog},"cycle":${simulationTime}}\n"""
    )
  }

  override protected def implicitClock: Clock = clockGen.clock.asClock

  override protected def implicitReset: Reset = clockGen.reset
}
