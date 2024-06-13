// SPDX-License-Identifier: GPL-3.0
// SPDX-FileCopyrightText: 2015-2019 Ultra-Embedded.com <admin@ultra-embedded.com>
// SPDX-FileCopyrightText: 2024 Beijing Institute of Open Source Chip
// TODO: change package to oscc
package oscc.sdramcontroller

import chisel3._
import chisel3.ltl.{CoverProperty, Sequence}

// This is what RTL designer need to implement, as well as necessary verification signal definitions.

/** The RTL here is rewrite from [[https://github.com/ultraembedded/core_sdram_axi4]].
  */
trait SDRAMControllerDV extends HasSDRAMControllerInterface {
  object DV extends layer.Layer(layer.Convention.Bind) {
    object Cover extends layer.Layer(layer.Convention.Bind)
    object Assert extends layer.Layer(layer.Convention.Bind)
  }
  // Place to write SVA.
  layer.block(DV) {
    val readRequestHoldStatus = probe.read(dv.readRequestHoldStatus)
    // Add functional coverage here.
    layer.block(DV.Cover) {
      CoverProperty(
        prop = Sequence.BoolSequence(readRequestHoldStatus),
        clock = Some(clock),
        disable = None,
        label = Some("READ_REQUEST_HOLD")
      )
    }

    // Add assertion here
    layer.block(DV.Assert) {
      
    }
  }
}
