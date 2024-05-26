// SPDX-License-Identifier: GPL-3.0
// SPDX-FileCopyrightText: 2015-2019 Ultra-Embedded.com <admin@ultra-embedded.com>
// SPDX-FileCopyrightText: 2024 Beijing Institute of Open Source Chip
// TODO: change package to oscc
package oscc.sdramcontroller

import chisel3._
import chisel3.util.{MuxLookup, Cat, Fill, switch, is, Mux1H}
import org.chipsalliance.amba.axi4.bundle.`enum`.burst.{FIXED, INCR, WARP}

// This is what RTL designer need to implement, as well as necessary verification signal definitions.

/** The RTL here is rewrite from [[https://github.com/ultraembedded/core_sdram_axi4]].
  */
trait SDRAMControllerRTL extends HasSDRAMControllerInterface {
  // TODO: use Mux1H for selection
  /** Calculate the next address of AXI4 bus. */
  private def calculateAddressNext(addr: UInt, axType: UInt, axLen: UInt): UInt =
    MuxLookup(axType, addr + 4.U) (
      Seq(
        FIXED -> 0.U,
        WARP -> {
          val mask = MuxLookup(axLen, "h3f".U(32.W)) (
            Seq(
              "d0".U  -> "h03".U,
              "d1".U  -> "h07".U,
              "d3".U  -> "h0F".U,
              "d7".U  -> "h1F".U,
              "d15".U -> "h3F".U
            )
          )
          (addr & (~mask).asUInt) | ((addr + 4.U) & mask)
        },
        INCR -> (addr + 4.U)
      )
    )

  /** First In First Out module */
  private class FIFO(WIDTH: Int = 8, DEPTH: Int = 4, ADDR_W: Int = 2) extends Module {
    val io = IO(new Bundle {
      /** FIFO clock */
      val clk_i = Input(Clock())
      /** FIFO reset */
      val rst_i = Input(Bool())
      /** FIFO data input */
      val data_in_i = Input(UInt(WIDTH.W))
      /** FIFO data push request */
      val push_i = Input(Bool())
      /** FIFO data pop request */
      val pop_i = Input(Bool())
      /** FIFO data output */
      val data_out_o = Output(UInt(WIDTH.W))
      /** FIFO accept signal, if it's true, FIFO can input data */
      val accept_o = Output(Bool())
      /** FIFO valid signal, if it's true, FIFO can output data */
      val valid_o = Output(Bool())
    })

    /** FIFO count */
    private val COUNT_W = ADDR_W + 1

    withClockAndReset(io.clk_i, io.rst_i) {
      /** FIFO buffer */
      val ram = RegInit(VecInit.fill(DEPTH)(0.U(WIDTH.W)))
      /** FIFO read pointer */
      val rd_ptr = RegInit(0.U(ADDR_W.W))
      /** FIFO write pointer */
      val wr_ptr = RegInit(0.U(ADDR_W.W))
      /** FIFO counter */
      val count = RegInit(0.U(COUNT_W.W))

      /** If read/write signals handshake, the corresponding pointer++, for
        * write operation, save input data to RAM pointed to by write pointer.
        */
      when (io.push_i && io.accept_o) {
        ram(wr_ptr) := io.data_in_i
        wr_ptr := wr_ptr + 1.U
      }
      when (io.pop_i && io.valid_o) {
        rd_ptr := rd_ptr + 1.U
      }

      /** Counter represent the status of read/write, if read signals handshake,
        * counter++, if write signals handshake, counter--
        */
      when ((io.push_i && io.accept_o) && !(io.pop_i && io.valid_o)) {
        count := count + 1.U
      }.elsewhen (!(io.push_i && io.accept_o) && (io.pop_i && io.valid_o)) {
        count := count - 1.U
      }

      /** Use counter to control whether to input or output data. Read operation
       *  is combinatorial, data only depends on the read pointer . */
      io.accept_o   := (count =/= DEPTH.U)
      io.valid_o    := (count =/= 0.U)
      io.data_out_o := ram(rd_ptr)
    }
  }

  withClockAndReset(clock, reset) {
    // ************************************************************************
    // SDRAM Request and Buffer
    // ************************************************************************
    /** SDRAM read/write request length */
    val req_len_q = RegInit(0.U(8.W))
    /** SDRAM read/write addr */
    val req_addr_q = RegInit(0.U(32.W))
    /** SDRAM write request enable
      * @todo change to Bool type.
      */
    val req_wr_q = RegInit(false.B)
    /** SDRAM read request enable
      * @todo change to [[Bool]] type.
      */
    val req_rd_q = RegInit(false.B)
    /** SDRAM read/write request id */
    val req_id_q = RegInit(0.U(4.W))
    /** SDRAM read/write burst type */
    val req_axburst_q = RegInit(0.U(2.W))
    /** SDRAM read/write burst length */
    val req_axlen_q = RegInit(0.U(8.W))
    /** SDRAM read/write priority
      * @todo change to [[Bool]] type. and add more documentation.
      */
    val req_prio_q = RegInit(false.B)

    /** SDRAM write strb, it cotains both enable and mask functions. when it
     * don't equal 4'b0000, it represent write is enable.
     */
    val ram_wr = WireInit(0.U(4.W))
    /** SDRAM read enalbe */
    val ram_rd = WireInit(0.U(4.W))
    /** Whether SDRAM can accept data
      * @todo change to [[Bool]] type.
      */
    val ram_accept = WireInit(false.B)

    /** When SDRAM mode is brust, let it perform read or write operation
     * continuously before request ends.
     */
    when ((ram_wr =/= 0.U || ram_rd === 1.U) && ram_accept) {
      when (req_len_q === 0.U) {
        req_rd_q := false.B
        req_wr_q := false.B
      }
      req_addr_q := calculateAddressNext(req_addr_q, req_axburst_q, req_axlen_q)
      req_len_q := req_len_q - 1.U
    }

    /** When read/write handshake happens, update related request registers. */
    when (axi.aw.valid && axi.aw.ready) {
      when (axi.w.valid && axi.w.ready) {
        req_wr_q := !axi.w.bits.last
        req_len_q := axi.aw.bits.len - 1.U
        req_id_q := axi.aw.bits.id
        req_axburst_q := axi.aw.bits.burst
        req_axlen_q := axi.aw.bits.len
        req_addr_q := calculateAddressNext(axi.aw.bits.addr,
          axi.aw.bits.burst,
          axi.aw.bits.len)
      }.otherwise {
        req_wr_q := true.B
        req_len_q := axi.aw.bits.len
        req_id_q := axi.aw.bits.id
        req_axburst_q := axi.aw.bits.burst
        req_axlen_q := axi.aw.bits.len
        req_addr_q := axi.aw.bits.addr
      }
      req_prio_q := !req_prio_q
    }.elsewhen (axi.ar.valid && axi.ar.ready) {
      req_rd_q := (axi.ar.bits.len =/= 0.U)
      req_len_q := axi.ar.bits.len - 1.U
      req_addr_q := calculateAddressNext(axi.ar.bits.addr,
        axi.ar.bits.burst,
        axi.ar.bits.len)
      req_id_q := axi.ar.bits.id
      req_axburst_q := axi.ar.bits.burst
      req_axlen_q := axi.ar.bits.len
      req_prio_q := !req_prio_q
    }

    /** SDRAM read request hold status.
      * @todo change to Bool type.
      */
    val req_hold_rd_q = RegInit(false.B)
    /** SDRAM write request hold status
      * @todo change to Bool type.
      */
    val req_hold_wr_q = RegInit(false.B)

    /** When SDRAM read/write request is enable and cannot accept data, assert
      * corresponding hold status, otherwise deassert.
      */
    when(ram_rd === 1.U && !ram_accept) {
      req_hold_rd_q := true.B
    }.elsewhen(ram_accept) {
      req_hold_rd_q := false.B
    }
    when(ram_wr =/= 0.U && !ram_accept) {
      req_hold_wr_q := true.B
    }.elsewhen(ram_accept) {
      req_hold_wr_q := true.B
    }

    // ------------------------------------------------------------------------
    // Request tracking
    // ------------------------------------------------------------------------
    /**  SDRAM request push */
    val req_push_w = ((ram_rd === 1.U) || (ram_wr =/= 0.U)) && ram_accept
    /** SDRAM request input */
    val req_in_r = RegInit(0.U(6.W))
    /** SDRAM request output valid */
    val req_out_valid_w = WireInit(false.B)
    /** SDRAM request out */
    val req_out_w = WireInit(0.U(6.W))
    /** SDRAM response accept */
    val resp_accept_w = WireInit(false.B)
    /** SDRAM request FIFO accept */
    val req_fifo_accept_w = WireInit(false.B)
    /** SDRAM read data */
    val ram_read_data_w = WireInit(0.U(32.W))
    /** SDRAM ack enable */
    val ram_ack_w = WireInit(false.B)
    /** SDRAM accept data enable */
    val ram_accept_w = WireInit(false.B)

    when (axi.ar.valid && axi.ar.ready) {
      req_in_r := Cat(1.U(1.W), axi.ar.bits.len === 0.U, axi.ar.bits.id)
    }.elsewhen(axi.aw.valid && axi.aw.ready) {
      req_in_r := Cat(0.U(1.W), axi.aw.bits.len === 0.U, axi.aw.bits.id)
    }.otherwise {
      req_in_r := Cat(ram_rd, req_len_q === 0.U, req_id_q)
    }

    val u_requests = Module(new FIFO(6))
    u_requests.io.clk_i := clock
    u_requests.io.rst_i := reset
    u_requests.io.data_in_i := req_in_r
    u_requests.io.push_i := req_push_w
    req_fifo_accept_w := u_requests.io.accept_o
    u_requests.io.pop_i := resp_accept_w
    req_out_w := u_requests.io.data_out_o
    req_out_valid_w := u_requests.io.valid_o

    val resp_is_write_w = Mux(req_out_valid_w, ~req_out_w(5), false.B)
    val resp_is_read_w = Mux(req_out_valid_w, req_out_w(5), false.B)
    val resp_is_last_w = req_out_w(4)
    val resp_id_w = req_out_w(3, 0)

    // ------------------------------------------------------------------------
    // Response buffering
    // ------------------------------------------------------------------------
    val resp_valid_w = WireInit(false.B)

    val u_response = Module(new FIFO(32))
    u_response.io.clk_i := clock
    u_response.io.rst_i := reset
    u_response.io.data_in_i := ram_read_data_w
    u_response.io.push_i := ram_ack_w
    u_response.io.accept_o := DontCare
    u_response.io.pop_i := resp_accept_w
    axi.r.bits.data := u_response.io.data_out_o
    resp_valid_w := u_response.io.valid_o

    // ------------------------------------------------------------------------
    // SDRAM Request
    // ------------------------------------------------------------------------
    val write_prio_w = (req_prio_q && !req_hold_rd_q) || req_hold_wr_q
    val read_prio_w = (!req_prio_q && !req_hold_wr_q) || req_hold_rd_q

    val write_active_w = (axi.aw.valid || req_wr_q) &&
      !req_rd_q &&
      req_fifo_accept_w &&
      (write_prio_w || req_wr_q || !axi.ar.valid)
    val read_active_w = (axi.ar.valid || req_rd_q) &&
      !req_wr_q &&
      req_fifo_accept_w &&
      (read_prio_w || req_rd_q || !axi.aw.valid)

    axi.aw.ready := write_active_w && !req_wr_q && ram_accept_w &&
      req_fifo_accept_w
    axi.w.ready := write_active_w && ram_accept_w &&
      req_fifo_accept_w
    axi.ar.ready := read_active_w && !req_rd_q && ram_accept_w &&
      req_fifo_accept_w

    val addr_w = Mux(req_wr_q || req_rd_q,
      req_addr_q,
      Mux(write_active_w, axi.aw.bits.addr, axi.ar.bits.addr))

    val wr_w = write_active_w && axi.w.valid
    val rd_w = read_active_w

    val ram_addr_w = addr_w
    val ram_write_data_w = axi.w.bits.data
    val ram_rd_w = rd_w
    val ram_wr_w = Mux(wr_w, axi.w.bits.strb, 0.U(4.W))

    // ------------------------------------------------------------------------
    // SDRAM Response
    // ------------------------------------------------------------------------
    axi.b.valid := resp_valid_w && resp_is_write_w.asBool && resp_is_last_w
    axi.b.bits.resp := 0.U(2.W)
    axi.b.bits.id := resp_id_w
    axi.b.bits.user := 0.U

    axi.r.valid := resp_valid_w && resp_is_read_w
    axi.r.bits.resp := 0.U(2.W)
    axi.r.bits.id := resp_id_w
    axi.r.bits.last := resp_is_last_w
    axi.r.bits.user := 0.U

    resp_accept_w := (axi.r.valid && axi.r.ready) ||
      (axi.b.valid && axi.b.ready) ||
      (resp_valid_w && resp_is_write_w.asBool && !resp_is_last_w)



    // ************************************************************************
    // SDRAM Controller
    // ************************************************************************
    // ------------------------------------------------------------------------
    // Key Params
    // ------------------------------------------------------------------------
    val SDRAM_MHZ              = 50
    val SDRAM_ADDR_W           = 24
    val SDRAM_COL_W            = 9
    val SDRAM_READ_LATENCY     = 2

    // ------------------------------------------------------------------------
    // Defines / Local params
    // ------------------------------------------------------------------------
    val SDRAM_BANK_W          = 2
    val SDRAM_DQM_W           = 2
    val SDRAM_BANKS           = 1 << SDRAM_BANK_W
    val SDRAM_ROW_W           = SDRAM_ADDR_W - SDRAM_COL_W - SDRAM_BANK_W
    val SDRAM_REFRESH_CNT     = 1 << SDRAM_ROW_W
    val SDRAM_START_DELAY     = 100000 / (1000 / SDRAM_MHZ) // 100uS
    val SDRAM_REFRESH_CYCLES  = (64000 * SDRAM_MHZ) / SDRAM_REFRESH_CNT - 1

    val CMD_W             = 4
    val CMD_NOP           = "b0111".U(4.W)
    val CMD_ACTIVE        = "b0011".U(4.W)
    val CMD_READ          = "b0101".U(4.W)
    val CMD_WRITE         = "b0100".U(4.W)
    val CMD_PRECHARGE     = "b0010".U(4.W)
    val CMD_REFRESH       = "b0001".U(4.W)
    val CMD_LOAD_MODE     = "b0000".U(4.W)

    // Mode: Burst Length = 4 bytes, CAS=2
    val MODE_REG          = Cat("b000".U(3.W), 0.U(1.W), 0.U(2.W),
      "b010".U(3.W), 0.U(1.W),
      "b001".U(3.W))

    // SM states
    val STATE_W           = 4
    val STATE_INIT        = 0.U(4.W)
    val STATE_DELAY       = 1.U(4.W)
    val STATE_IDLE        = 2.U(4.W)
    val STATE_ACTIVATE    = 3.U(4.W)
    val STATE_READ        = 4.U(4.W)
    val STATE_READ_WAIT   = 5.U(4.W)
    val STATE_WRITE0      = 6.U(4.W)
    val STATE_WRITE1      = 7.U(4.W)
    val STATE_PRECHARGE   = 8.U(4.W)
    val STATE_REFRESH     = 9.U(4.W)

    val AUTO_PRECHARGE    = 10
    val ALL_BANKS         = 10

    val SDRAM_DATA_W      = 16

    val CYCLE_TIME_NS     = 1000 / SDRAM_MHZ

    // SDRAM timing
    val SDRAM_TRCD_CYCLES = (20 + (CYCLE_TIME_NS - 1)) / CYCLE_TIME_NS
    val SDRAM_TRP_CYCLES  = (20 + (CYCLE_TIME_NS - 1)) / CYCLE_TIME_NS
    val SDRAM_TRFC_CYCLES = (60 + (CYCLE_TIME_NS - 1)) / CYCLE_TIME_NS

    // ------------------------------------------------------------------------
    // External Interface
    // ------------------------------------------------------------------------
    val ram_req_w = (ram_wr_w =/= 0.U) || ram_rd_w

    // ------------------------------------------------------------------------
    // Registers / Wires
    // ------------------------------------------------------------------------
    val command_q = RegInit(CMD_NOP)
    val addr_q = RegInit(0.U(SDRAM_ROW_W.W))
    val data_q = RegInit(0.U(SDRAM_DATA_W.W))
    val data_rd_en_q = RegInit(true.B)
    val dqm_q = RegInit(0.U(SDRAM_DQM_W.W))
    val cke_q = RegInit(false.B)
    val bank_q = RegInit(0.U(SDRAM_BANK_W.W))

    // Buffer half word during read and write commands
    val data_buffer_q = RegInit(0.U(SDRAM_DATA_W.W))
    val dqm_buffer_q = RegInit(0.U(SDRAM_DQM_W.W))
    val sdram_data_in_w = WireInit(0.U(SDRAM_DATA_W.W))

    val refresh_q = RegInit(false.B)

    val row_open_q = RegInit(0.U(SDRAM_BANKS.W))
    val active_row_q = VecInit.fill(SDRAM_BANKS)(0.U(SDRAM_BANK_W.W))

    val state_q = RegInit(0.U(STATE_W.W))
    val next_state_r = RegInit(0.U(STATE_W.W))
    val target_state_r = RegInit(0.U(STATE_W.W))
    val target_state_q = RegInit(STATE_IDLE)
    val delay_state_q = RegInit(STATE_IDLE)

    // Address bits
    val addr_col_w  = Cat(Fill(SDRAM_ROW_W - SDRAM_COL_W, 0.U(1.W)),
      ram_addr_w(SDRAM_COL_W, 2),
      0.U(1.W))
    val addr_row_w  = ram_addr_w(SDRAM_ADDR_W, SDRAM_COL_W + 2 + 1)
    val addr_bank_w = ram_addr_w(SDRAM_COL_W + 2, SDRAM_COL_W + 2 - 1)

    // ------------------------------------------------------------------------
    // State Machine
    // ------------------------------------------------------------------------
    next_state_r := state_q
    target_state_r := target_state_q

    switch (state_q) {
      is (STATE_INIT) {
        when (refresh_q) {
          next_state_r := STATE_IDLE
        }
      }
      is (STATE_IDLE) {
        // Pending refresh
        // Note: tRAS (open row time) cannot be exceeded due to periodic
        //        auto refreshes.
        when (refresh_q) {
          // Close open rows, then refresh
          when (row_open_q =/= 0.U) {
            next_state_r := STATE_PRECHARGE
          }.otherwise {
            next_state_r := STATE_REFRESH
          }
          target_state_r := STATE_REFRESH
        }.elsewhen (ram_req_w) {
          // Open row hit
          when (row_open_q(addr_bank_w) && (addr_row_w === active_row_q(addr_bank_w))) {
            when (!ram_rd_w) {
              next_state_r := STATE_WRITE0
            }.otherwise {
              next_state_r := STATE_READ
            }
            // Row miss, close row, open new row
          }.elsewhen (row_open_q(addr_bank_w)) {
            next_state_r := STATE_PRECHARGE
            when (!ram_rd_w) {
              target_state_r := STATE_WRITE0
            }.otherwise {
              target_state_r := STATE_READ
            }
            // No open row, open row
          }.otherwise {
            next_state_r := STATE_ACTIVATE
            when (!ram_rd_w) {
              target_state_r := STATE_WRITE0
            }.otherwise {
              target_state_r := STATE_READ
            }
          }
        }
      }
      is (STATE_ACTIVATE) {
        // Proceed to read or write state
        next_state_r := target_state_r
      }
      is (STATE_READ) {
        next_state_r := STATE_READ_WAIT
      }
      is (STATE_READ_WAIT) {
        next_state_r := STATE_IDLE
        // Another pending read request (with no refresh pending)
        when (!refresh_q && ram_req_w && ram_rd_w) {
          // Open row hit
          when (row_open_q(addr_bank_w) && (addr_row_w === active_row_q(addr_bank_w))) {
            next_state_r := STATE_READ
          }
        }
      }
      is (STATE_WRITE0) {
        next_state_r := STATE_WRITE1
      }
      is (STATE_WRITE1) {
        next_state_r := STATE_IDLE
        // Another pending write request (with no refresh pending)
        when (!refresh_q && ram_req_w && ram_wr_w =/= 0.U) {
          // Open row hit
          when (row_open_q(addr_bank_w) && (addr_row_w === active_row_q(addr_bank_w))) {
            next_state_r := STATE_WRITE0
          }
        }
      }
      is (STATE_PRECHARGE) {
        // Closing row to perform refresh
        when (target_state_r === STATE_REFRESH) {
          next_state_r := STATE_REFRESH
          // Must be closing row to open another
        }.otherwise {
          next_state_r := STATE_ACTIVATE
        }
      }
      is (STATE_REFRESH) {
        next_state_r := STATE_IDLE
      }
      is (STATE_DELAY) {
        next_state_r := delay_state_q
      }
    }

    // ------------------------------------------------------------------------
    // Delays
    // ------------------------------------------------------------------------
    val DELAY_W = 4

    val delay_q = RegInit(0.U(DELAY_W.W))
    val delay_r = RegInit(0.U(DELAY_W.W))

    delay_r := 0.U(DELAY_W.W)

    switch (state_q) {
      is (STATE_ACTIVATE) {
        // tRCD (ACTIVATE -> READ / WRITE)
        delay_r := SDRAM_TRCD_CYCLES.asUInt
      }
      is (STATE_READ_WAIT) {
        delay_r := SDRAM_READ_LATENCY.asUInt
        // Another pending read request (with no refresh pending)
        when (!refresh_q && ram_req_w && ram_rd_w) {
          // Open row hit
          when (row_open_q(addr_bank_w) && (addr_row_w === active_row_q(addr_bank_w))) {
            delay_r := 0.U(DELAY_W.W)
          }
        }
      }
      is (STATE_PRECHARGE) {
        // tRP (PRECHARGE -> ACTIVATE)
        delay_r := SDRAM_TRP_CYCLES.asUInt
      }
      is (STATE_REFRESH) {
        // tRFC
        delay_r := SDRAM_TRFC_CYCLES.asUInt
      }
      is (STATE_DELAY) {
        delay_r := delay_q - 1.U(DELAY_W.W)
      }
    }

    // Record target state
    target_state_q := target_state_r

    // Record delayed state
    delay_q := delay_r

    // ------------------------------------------------------------------------
    // Refresh counter
    // ------------------------------------------------------------------------
    val REFRESH_CNT_W = 17

    // Bug Here
    val refresh_timer_q = RegInit(0.U(REFRESH_CNT_W.W))
    when (refresh_timer_q === 0.U(REFRESH_CNT_W.W)) {
      refresh_timer_q := SDRAM_REFRESH_CYCLES.asUInt
    }.otherwise {
      refresh_timer_q := refresh_timer_q - 1.U
    }

    when (refresh_timer_q === 0.U(REFRESH_CNT_W.W)) {
      refresh_q := true.B
    }.otherwise {
      refresh_q := false.B
    }

    // ------------------------------------------------------------------------
    // Input sampling
    // ------------------------------------------------------------------------
    val sample_data0_q = RegInit(0.U(SDRAM_DATA_W.W))
    sample_data0_q := sdram_data_in_w

    val sample_data_q = RegInit(0.U(SDRAM_DATA_W.W))
    sample_data_q := sample_data0_q

    // ------------------------------------------------------------------------
    // Command Output
    // ------------------------------------------------------------------------
    command_q := CMD_NOP
    addr_q := 0.U(SDRAM_ROW_W.W)
    bank_q := 0.U(SDRAM_BANK_W.W)
    data_rd_en_q := true.B

    switch (state_q) {
      is (STATE_INIT) {
        when (refresh_q === 50.U) {
          cke_q := true.B
        }.elsewhen (refresh_timer_q === 40.U) {
          command_q := CMD_PRECHARGE
          // TODO: fix me: addr_q(ALL_BANKS) := 1.U(1.W)
          addr_q := Cat(addr_q(SDRAM_ROW_W - 1, ALL_BANKS + 1), 1.U, addr_q(ALL_BANKS - 1, 0))
        }.elsewhen (refresh_timer_q === 20.U || refresh_timer_q === 30.U) {
          command_q := CMD_REFRESH
        }.elsewhen (refresh_timer_q === 10.U) {
          command_q := CMD_LOAD_MODE
          addr_q := MODE_REG
        }.otherwise {
          command_q := CMD_NOP
          addr_q := 0.U(SDRAM_ROW_W.W)
          bank_q := 0.U(SDRAM_BANK_W.W)
        }
      }
      is (STATE_ACTIVATE) {
        command_q := CMD_ACTIVE
        addr_q := addr_row_w
        bank_q := addr_bank_w

        active_row_q(addr_bank_w) := addr_row_w
        // TODO: fix me: row_open_q(addr_bank_w) := 1.U(1.W)
        row_open_q := MuxLookup(addr_bank_w, row_open_q) (
          Seq(
            0.U -> Cat(row_open_q(SDRAM_BANKS - 1, 1), 1.U),
            1.U -> Cat(row_open_q(SDRAM_BANKS - 1, 2), 1.U, row_open_q(0)),
            2.U -> Cat(row_open_q(SDRAM_BANKS - 1, 3), 1.U, row_open_q(SDRAM_BANKS - 3, 0)),
            3.U -> Cat(1.U,                                 row_open_q(SDRAM_BANKS - 2, 0))
          )
        )
      }
      is (STATE_PRECHARGE) {
        when (target_state_r === STATE_REFRESH) {
          command_q := CMD_PRECHARGE
          // TODO: fix me: addr_q(ALL_BANKS) := 1.U(1.W)
          addr_q := Cat(addr_q(SDRAM_ROW_W - 1, ALL_BANKS + 1), 1.U, addr_q(ALL_BANKS - 1, 0))
          row_open_q := 0.U(SDRAM_BANKS.W)
        }.otherwise {
          command_q := CMD_PRECHARGE
          // TODO: fix me: addr_q(ALL_BANKS) := 0.U(1.W)
          addr_q := Cat(addr_q(SDRAM_ROW_W - 1, ALL_BANKS + 1), 0.U, addr_q(ALL_BANKS - 1, 0))
          bank_q := addr_bank_w
          // TODO: fix me: row_open_q(addr_bank_w) := 0.U(1.W)
          row_open_q := MuxLookup(addr_bank_w, row_open_q) (
            Seq(
              0.U -> Cat(row_open_q(SDRAM_BANKS - 1, 1), 0.U),
              1.U -> Cat(row_open_q(SDRAM_BANKS - 1, 2), 0.U, row_open_q(0)),
              2.U -> Cat(row_open_q(SDRAM_BANKS - 1, 3), 0.U, row_open_q(SDRAM_BANKS - 3, 0)),
              3.U -> Cat(1.U,                                 row_open_q(SDRAM_BANKS - 2, 0))
            )
          )
        }
      }
      is (STATE_REFRESH) {
        command_q := CMD_REFRESH
        addr_q := 0.U(SDRAM_ROW_W.W)
        bank_q := 0.U(SDRAM_BANK_W.W)
      }
      is (STATE_READ) {
        command_q := CMD_READ
        addr_q := addr_col_w
        bank_q := addr_bank_w

        // TODO: fix me: addr_q(AUTO_PRECHARGE) := 0.U(1.W)
        addr_q := Cat(addr_q(SDRAM_ROW_W - 1, AUTO_PRECHARGE + 1), 0.U, addr_q(AUTO_PRECHARGE - 1, 0))
        dqm_q := 0.U(SDRAM_DQM_W.W)
      }
      is (STATE_WRITE0) {
        command_q := CMD_WRITE
        addr_q := addr_col_w
        bank_q := addr_bank_w
        data_q := ram_write_data_w(15, 0)

        // TODO: fix me: addr_q(AUTO_PRECHARGE) := 0.U(1.W)
        addr_q := Cat(addr_q(SDRAM_ROW_W - 1, AUTO_PRECHARGE + 1), 0.U, addr_q(AUTO_PRECHARGE - 1, 0))
        dqm_q := ~ram_wr_w(1, 0)
        dqm_buffer_q := ~ram_wr_w(3, 2)

        data_rd_en_q := false.B
      }
      is (STATE_WRITE1) {
        command_q := CMD_NOP
        data_q := data_buffer_q

        // TODO: fix me: addr_q(AUTO_PRECHARGE) := 0.U(1.W)
        addr_q := Cat(addr_q(SDRAM_ROW_W - 1, AUTO_PRECHARGE + 1), 0.U, addr_q(AUTO_PRECHARGE - 1, 0))
        dqm_q := dqm_buffer_q
      }
    }

    // ------------------------------------------------------------------------
    // Record read events
    // ------------------------------------------------------------------------
    val rd_q = RegInit(0.U((SDRAM_READ_LATENCY + 2).W))
    rd_q := Cat(rd_q(SDRAM_READ_LATENCY, 0), state_q === STATE_READ)

    // ------------------------------------------------------------------------
    // Data buffer
    // ------------------------------------------------------------------------
    when (state_q === STATE_WRITE0) {
      data_buffer_q := ram_write_data_w(31, 16)
    }.elsewhen (rd_q(SDRAM_READ_LATENCY + 1)) {
      data_buffer_q := sample_data_q
    }

    ram_read_data_w := Cat(sample_data_q, data_buffer_q)

    // ------------------------------------------------------------------------
    // ACK
    // ------------------------------------------------------------------------
    val ack_q = RegInit(false.B)
    when (state_q === STATE_WRITE1) {
      ack_q := true.B
    }.elsewhen (rd_q(SDRAM_READ_LATENCY + 1)) {
      ack_q := true.B
    }.otherwise {
      ack_q := false.B
    }

    ram_ack_w := ack_q
    ram_accept_w := (state_q === STATE_READ || state_q === STATE_WRITE0)

    // ------------------------------------------------------------------------
    // SDRAM I/O
    // ------------------------------------------------------------------------
    // TODO: this is forbidden in RTL, use CTS blackbox instead.
    sdram.ck.foreach(_ := (~clock.asBool).asBool.asClock)
    sdram.cke := cke_q
    sdram.cs  := command_q(3)
    sdram.ras := command_q(2)
    sdram.cas := command_q(1)
    sdram.we  := command_q(0)
    sdram.dqm := dqm_q
    sdram.ba  := bank_q
    sdram.a   := addr_q
    sdram.dqDir := ~data_rd_en_q
    sdram.dqo   := data_q

    sdram_data_in_w := sdram.dqi
  }
}
