import mill._
import mill.scalalib._
import mill.define.{TaskModule, Command}
import mill.scalalib.publish._
import mill.scalalib.scalafmt._
import $file.dependencies.chisel.build
import $file.dependencies.`chisel-interface`.common
import $file.common

object v {
  val scala = "2.13.14"
  val mainargs = ivy"com.lihaoyi::mainargs:0.7.0"
}

object chisel extends Chisel

trait Chisel extends millbuild.dependencies.chisel.build.Chisel {
  def crossValue = v.scala
  override def millSourcePath = os.pwd / "dependencies" / "chisel"
}

object axi4 extends AXI4

trait AXI4 extends millbuild.dependencies.`chisel-interface`.common.AXI4Module {
  override def millSourcePath =
    os.pwd / "dependencies" / "chisel-interface" / "axi4"
  def scalaVersion = v.scala

  def mainargsIvy = v.mainargs

  def chiselModule = Some(chisel)
  def chiselPluginJar = T(Some(chisel.pluginModule.jar()))
  def chiselIvy = None
  def chiselPluginIvy = None
}

object sdram extends SDRAM

trait SDRAM
    extends millbuild.dependencies.`chisel-interface`.common.SDRAMModule {
  override def millSourcePath =
    os.pwd / "dependencies" / "chisel-interface" / "sdram"
  def scalaVersion = v.scala

  def mainargsIvy = v.mainargs

  def chiselModule = Some(chisel)
  def chiselPluginJar = T(Some(chisel.pluginModule.jar()))
  def chiselIvy = None
  def chiselPluginIvy = None
}

object sdramcontroller
    extends millbuild.common.SDRAMControllerModule
    with ScalafmtModule {
  def millSourcePath = os.pwd / "sdramcontroller"
  def scalaVersion = T(v.scala)
  def chiselModule = Some(chisel)
  def chiselPluginModule = Some(chisel.pluginModule)
  def sdramModule = sdram
  def axi4Module = axi4
  def mainargsIvy = v.mainargs
}
