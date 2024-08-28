// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2024 Jiuyang Liu <liu@jiuyang.me>

import mill._
import mill.scalalib._
import mill.define.{Command, TaskModule}
import mill.scalalib.publish._
import mill.scalalib.scalafmt._
import mill.scalalib.TestModule.Utest
import mill.util.Jvm
import coursier.maven.MavenRepository
import $file.dependencies.chisel.build
import $file.dependencies.`chisel-interface`.common
import $file.common

object deps {
  val scalaVer = "2.13.14"
  val mainargs = ivy"com.lihaoyi::mainargs:0.5.0"
  val oslib = ivy"com.lihaoyi::os-lib:0.9.1"
  val upickle = ivy"com.lihaoyi::upickle:3.3.1"
}

object chisel extends Chisel

trait Chisel extends millbuild.dependencies.chisel.build.Chisel {
  def crossValue = deps.scalaVer
  override def millSourcePath = os.pwd / "dependencies" / "chisel"
}

object axi4 extends AXI4
trait AXI4 extends millbuild.dependencies.`chisel-interface`.common.AXI4Module {
  override def millSourcePath =
    os.pwd / "dependencies" / "chisel-interface" / "axi4"
  def scalaVersion = T(deps.scalaVer)

  def chiselModule = Some(chisel)
  def chiselPluginJar = T(Some(chisel.pluginModule.jar()))
  def chiselIvy = None
  def chiselPluginIvy = None
  def mainargsIvy: Dep = deps.mainargs
}

object dwbb extends DWBB
trait DWBB extends millbuild.dependencies.`chisel-interface`.common.DWBBModule {
  override def millSourcePath =
    os.pwd / "dependencies" / "chisel-interface" / "dwbb"
  def scalaVersion = T(deps.scalaVer)

  def mainargsIvy = deps.mainargs

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
  def scalaVersion = deps.scalaVer

  def mainargsIvy = deps.mainargs

  def chiselModule = Some(chisel)
  def chiselPluginJar = T(Some(chisel.pluginModule.jar()))
  def chiselIvy = None
  def chiselPluginIvy = None
}

object sdramcontroller
  extends millbuild.common.SDRAMControllerModule
    with ScalafmtModule {
  def millSourcePath = os.pwd / "sdramcontroller"
  def scalaVersion = T(deps.scalaVer)
  def axi4Module = axi4
  def dwbbModule = dwbb
  def sdramModule = sdram
  def mainargsIvy = deps.mainargs

  def chiselModule = Some(chisel)
  def chiselPluginJar = T(Some(chisel.pluginModule.jar()))
  def chiselPluginIvy = None
  def chiselIvy = None
}

object elaborator extends Elaborator
trait Elaborator extends millbuild.common.ElaboratorModule {
  def scalaVersion = T(deps.scalaVer)

  def panamaconverterModule = panamaconverter

  def circtInstallPath =
    T.input(PathRef(os.Path(T.ctx().env("CIRCT_INSTALL_PATH"))))

  def generators = Seq(sdramcontroller)

  def mainargsIvy = deps.mainargs

  def chiselModule = Some(chisel)
  def chiselPluginJar = T(Some(chisel.pluginModule.jar()))
  def chiselPluginIvy = None
  def chiselIvy = None
}

object panamaconverter extends PanamaConverter
trait PanamaConverter extends millbuild.dependencies.chisel.build.PanamaConverter {
  def crossValue = deps.scalaVer

  override def millSourcePath =
    os.pwd / "dependencies" / "chisel" / "panamaconverter"

  def scalaVersion = T(deps.scalaVer)
}
