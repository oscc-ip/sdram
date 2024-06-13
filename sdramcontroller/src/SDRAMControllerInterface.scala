// TODO: change package to oscc
package oscc.sdramcontroller

import chisel3._
import chisel3.experimental.SerializableModuleParameter
import chisel3.experimental.dataview.DataViewable
import chisel3.probe.Probe
import org.chipsalliance.amba.axi4.bundle._
import org.chipsalliance.jedec.sdram.{SDRAMChiselType, SDRAMParameter}
import upickle.default

import scala.collection.immutable.SeqMap

object SDRAMControllerParameter {
  implicit def rw: default.ReadWriter[SDRAMControllerParameter] =
    upickle.default.macroRW[SDRAMControllerParameter]
}

case class SDRAMControllerParameter(
                                     dataParameter: AXI4BundleParameter,
                                     sdramParameter: SDRAMParameter
                                   ) extends SerializableModuleParameter {
  require(dataParameter.supportId, "doesn't support id")
  require(dataParameter.supportLen, "doesn't support len")
  require(dataParameter.supportSize, "doesn't support size")
  require(dataParameter.supportBurst, "should support burst")
  require(dataParameter.supportStrb, "doesn't support strb")

  require(!dataParameter.supportLock, "doesn't support lock")
  require(!dataParameter.supportRegion, "doesn't support region")
  require(!dataParameter.supportCache, "doesn't support cache")
  require(!dataParameter.supportQos, "doesn't support qos")
  require(!dataParameter.supportResp, "doesn't support resp")
  require(!dataParameter.supportProt, "doesn't support prot")
  require(dataParameter.dataWidth == sdramParameter.dataWidth, "data width of axi and sdram should same, please inter busip before controller.")
}

class SDRAMControllerInterface(val parameter: SDRAMControllerParameter) extends Record {
  val elements: SeqMap[String, Data] = SeqMap.from(
    Seq(
      "clock" -> Input(Clock()),
      // TODO: we only support sync reset for now.
      "reset" -> Input(Bool()),
      "dataAXI" -> Flipped(verilog.irrevocable(parameter.dataParameter)),
      // TODO: add another parameter for control interface
      //       "controlAXI" -> Flipped(verilog.irrevocable(parameter.dataParameter)),
      // TODO: we should have two types of SDRAM: IO(has inout), Digital(no inout, has dir.)
      "sdram" -> new SDRAMChiselType(parameter.sdramParameter),
      "dv" -> Output(new SDRAMControllerProbe(parameter)),
    )
  )
  def clock: Clock = elements("clock").asInstanceOf[Clock]
  def reset: Bool = elements("reset").asInstanceOf[Bool]
  def data: AXI4RWIrrevocable = elements("dataAXI").asInstanceOf[AXI4RWIrrevocableVerilog].viewAs[AXI4RWIrrevocable]
//  def control: AXI4RWIrrevocable = elements("controlAXI").asInstanceOf[AXI4RWIrrevocableVerilog].viewAs[AXI4RWIrrevocable]
  def dv: SDRAMControllerProbe = elements("dv").asInstanceOf[SDRAMControllerProbe]
  def sdram: SDRAMChiselType = elements("sdram").asInstanceOf[SDRAMChiselType]
}

/** used to capture internal RTL signals as Cross Module Reference. */
class SDRAMControllerProbe(val parameter: SDRAMControllerParameter) extends Bundle {
  val readRequestHoldStatus: Bool = Probe(Bool())
}

trait HasSDRAMControllerInterface {
  val parameter: SDRAMControllerParameter
  val interface: SDRAMControllerInterface
  lazy val clock = interface.clock
  lazy val reset = interface.reset
  lazy val data = interface.data
//  lazy val control = interface.control
  lazy val sdram = interface.sdram
  lazy val dv = interface.dv
}