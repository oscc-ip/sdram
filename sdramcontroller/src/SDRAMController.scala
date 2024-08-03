// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2024 Jiuyang Liu <liu@jiuyang.me>
package oscc.sdramcontroller

import chisel3._
import chisel3.experimental.SerializableModule

class SDRAMController(val parameter: SDRAMControllerParameter)
    extends FixedIORawModule[SDRAMControllerInterface](
      new SDRAMControllerInterface(parameter)
    )
    with SerializableModule[SDRAMControllerParameter]
    with SDRAMControllerRTL
      with Public
      with ImplicitClock
      with ImplicitReset {
  lazy val interface: SDRAMControllerInterface = io

  def implicitClock: Clock = io.clock

  def implicitReset: Reset = io.reset
}
