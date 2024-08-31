// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2024 Jiuyang Liu <liu@jiuyang.me>
package oscc.sdramcontroller.elaborator

import mainargs._
import org.chipsalliance.amba.axi4.bundle.AXI4BundleParameter
import org.chipsalliance.chisel.elaborator.Elaborator
import org.chipsalliance.jedec.sdram.SDRAMParameter
import oscc.sdramcontroller.TestVerbatimParameter
import oscc.sdramcontroller.elaborator.SDRAMControllerMain._

import oscc.sdramcontroller.{SDRAMControllerTestBench, SDRAMControllerTestBenchParameter}

/** This is used for other tools, IP-XACT will also live here in the future. */
object SDRAMControllerTestBenchMain extends Elaborator {
  @main
  def config(@arg(name = "parameter") parameter: SDRAMControllerTestBenchParameterMain) =
    configImpl(parameter.convert)

  @main
  def design(
    @arg(name = "parameter") parameter:    os.Path = os.pwd / s"${getClass.getSimpleName.replace("$", "")}.json",
    @arg(name = "run-firtool") runFirtool: mainargs.Flag,
    @arg(name = "target-dir") targetDir:   os.Path
  ) = designImpl[SDRAMControllerTestBench, SDRAMControllerTestBenchParameter](
    parameter,
    runFirtool.value,
    targetDir
  )

  implicit def TestVerbatimParameterMainParser: ParserForClass[TestVerbatimParameterMain] =
    ParserForClass[TestVerbatimParameterMain]

  implicit def SDRAMControllerTestBenchParameterMainParser: ParserForClass[SDRAMControllerTestBenchParameterMain] =
    ParserForClass[SDRAMControllerTestBenchParameterMain]

  case class TestVerbatimParameterMain(
    @arg(name = "useAsyncReset") useAsyncReset:       Boolean,
    @arg(name = "initFunctionName") initFunctionName: String,
    @arg(name = "dumpFunctionName") dumpFunctionName: String,
    @arg(name = "clockFlipTick") clockFlipTick:       Int,
    @arg(name = "resetFlipTick") resetFlipTick:       Int) {
    def convert: TestVerbatimParameter = TestVerbatimParameter(
      useAsyncReset:    Boolean,
      initFunctionName: String,
      dumpFunctionName: String,
      clockFlipTick:    Int,
      resetFlipTick:    Int
    )
  }
  case class SDRAMControllerTestBenchParameterMain(
    @arg(name = "sdramControllerParameter") sdramControllerParameter: SDRAMControllerParameterMain,
    @arg(name = "testVerbatimParameter") testVerbatimParameter:       TestVerbatimParameterMain,
    @arg(name = "timeout") timeout:                                   Int) {
    def convert: SDRAMControllerTestBenchParameter =
      SDRAMControllerTestBenchParameter(sdramControllerParameter.convert, testVerbatimParameter.convert, timeout)
  }

  def main(args: Array[String]): Unit = ParserForMethods(this).runOrExit(args)
}
