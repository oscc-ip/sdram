// SPDX-FileCopyrightText: 2024 Beijing Institute of Open Source Chip
package oscc.sdramcontroller

import chisel3._
import chisel3.experimental.SerializableModuleParameter
import chisel3.experimental.dataview.DataViewable
import org.chipsalliance.amba.axi4.bundle._
import org.chipsalliance.jedec.sdram.{SDRAMChiselType, SDRAMParameter}
import upickle.default

import scala.collection.immutable.SeqMap

object SDRAMControllerParameter {
  implicit def rw: default.ReadWriter[SDRAMControllerParameter] =
    upickle.default.macroRW[SDRAMControllerParameter]
}

case class SDRAMControllerParameter(
  axiParameter:   AXI4BundleParameter,
  sdramParameter: SDRAMParameter)
    extends SerializableModuleParameter {
  require(axiParameter.supportId, "doesn't support id")
  require(axiParameter.supportLen, "doesn't support len")
  require(axiParameter.supportSize, "doesn't support size")
  require(axiParameter.supportBurst, "should support burst")
  require(axiParameter.supportStrb, "doesn't support strb")

  require(!axiParameter.supportLock, "doesn't support lock")
  require(!axiParameter.supportRegion, "doesn't support region")
  require(!axiParameter.supportCache, "doesn't support cache")
  require(!axiParameter.supportQos, "doesn't support qos")
  require(!axiParameter.supportResp, "doesn't support resp")
  require(!axiParameter.supportProt, "doesn't support prot")
  // require(
  //   axiParameter.dataWidth == sdramParameter.dataWidth,
  //   "data width of axi and sdram should same, please inter busip before controller."
  // )
}

class SDRAMControllerInterface(val parameter: SDRAMControllerParameter) extends Record {
  val elements: SeqMap[String, Data] = SeqMap.from(
    Seq(
      "clock" -> Input(Clock()),
      // TODO: we only support sync reset for now.
      "reset" -> Input(Bool()),
      "AXI" -> Flipped(verilog.irrevocable(parameter.axiParameter)),
      // TODO: we should have two types of SDRAM: IO(has inout), Digital(no inout, has dir.)
      "SDRAM" -> new SDRAMChiselType(parameter.sdramParameter)
    )
  )
  def clock: Clock = elements("clock").asInstanceOf[Clock]
  def reset: Bool = elements("reset").asInstanceOf[Bool]
  def axi: AXI4RWIrrevocable = elements("AXI")
    .asInstanceOf[AXI4RWIrrevocableVerilog]
    .viewAs[AXI4RWIrrevocable]
  def sdram: SDRAMChiselType = elements("SDRAM").asInstanceOf[SDRAMChiselType]
}

trait HasSDRAMControllerInterface {
  lazy val clock = interface.clock
  lazy val reset = interface.reset
  lazy val axi = interface.axi
  lazy val sdram = interface.sdram
  val parameter: SDRAMControllerParameter
  val interface: SDRAMControllerInterface
}
