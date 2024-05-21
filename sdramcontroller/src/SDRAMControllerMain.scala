// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2024 Jiuyang Liu <liu@jiuyang.me>
package oscc.sdramcontroller

import mainargs._
import org.chipsalliance.amba.axi4.bundle.AXI4BundleParameter
import org.chipsalliance.jedec.sdram.SDRAMParameter

/** This is used for other tools, IP-XACT will also live here in the future. */
object SDRAMControllerMain extends Elaborator {
  @main
  case class AXI4BundleParameterMain(
                                      @arg(name = "idWidth") idWidth: Int,
                                      @arg(name = "dataWidth") dataWidth: Int,
                                      @arg(name = "addrWidth") addrWidth: Int,
                                    ) {
    def convert: AXI4BundleParameter = AXI4BundleParameter(
      idWidth,
      dataWidth,
      addrWidth,
      userReqWidth = 0,
      userDataWidth = 0,
      userRespWidth = 0,
      hasAW = true,
      hasW = true,
      hasB = true,
      hasAR = true,
      hasR = true,
      supportId = true,
      supportRegion = false,
      supportLen = true,
      supportSize = true,
      supportBurst = true,
      supportLock = false,
      supportCache = false,
      supportQos = false,
      supportStrb = true,
      supportResp = false,
      supportProt = false
    )
  }

  implicit def AXI4BundleParameterMainParser
  : ParserForClass[AXI4BundleParameterMain] = ParserForClass[AXI4BundleParameterMain]

  @main
  case class SDRAMParameterMain(
                                 @arg(name = "dataWidth") dataWidth: Int,
                                 @arg(name = "csWidth") csWidth: Int
                                    ) {
    def convert: SDRAMParameter = SDRAMParameter(
      dataWidth,
      csWidth
    )
  }

  implicit def SDRAMParameterMainParser
  : ParserForClass[SDRAMParameterMain] = ParserForClass[SDRAMParameterMain]


  @main
  case class SDRAMControllerParameterMain(
                                           @arg(name = "axiParameter") axiParameter: AXI4BundleParameterMain,
                                           @arg(name = "sdramParameter") sdramParameter: SDRAMParameterMain
                                ) {
    def convert: SDRAMControllerParameter = SDRAMControllerParameter(axiParameter.convert, sdramParameter.convert)
  }
  implicit def BufferParameterMainParser: ParserForClass[SDRAMControllerParameterMain] =
    ParserForClass[SDRAMControllerParameterMain]

  @main
  def config(@arg(name = "parameter") parameter: SDRAMControllerParameterMain) =
    configImpl(parameter.convert)

  @main
  def design(
              @arg(name = "parameter") parameter: os.Path =
              os.pwd / s"${getClass.getSimpleName.replace("$", "")}.json",
              @arg(name = "run-firtool") runFirtool: mainargs.Flag
            ) = designImpl[SDRAMController, SDRAMControllerParameter](parameter, runFirtool.value)
  def main(args: Array[String]): Unit = ParserForMethods(this).runOrExit(args)
}
