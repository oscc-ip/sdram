// SPDX-License-Identifier: GPL-3.0
// SPDX-FileCopyrightText: 2015-2019 Ultra-Embedded.com <admin@ultra-embedded.com>
// SPDX-FileCopyrightText: 2024 Beijing Institute of Open Source Chip
// TODO: change package to oscc
package oscc.sdramcontroller

import chisel3._
import chisel3.experimental.hierarchy.{Instance, Instantiate}
import chisel3.util._
import org.chipsalliance.amba.axi4.bundle.`enum`.burst.{FIXED, INCR, WARP}
import org.chipsalliance.dwbb.wrapper.DW_fifo_s1_sf.DW_fifo_s1_sf

// This is what RTL designer need to implement, as well as necessary verification signal definitions.

/** The RTL here is rewrite from
  * [[https://github.com/ultraembedded/core_sdram_axi4]].
  */
trait SDRAMControllerRTL extends HasSDRAMControllerInterface {
  // ==========================================================================
  // SDRAM Utils
  // ==========================================================================
  /** Calculate the next address of AXI4 bus. */
  private def calculateAddressNext(
      addr: UInt,
      axType: UInt,
      axLen: UInt
  ): UInt =
    MuxLookup(axType, addr + 4.U)(
      Seq(
        FIXED -> 0.U,
        WARP -> {
//          val mask = MuxLookup(axLen, "h3f".U(32.W))(
//            Seq(
//              "d0".U -> "h03".U,
//              "d1".U -> "h07".U,
//              "d3".U -> "h0F".U,
//              "d7".U -> "h1F".U,
//              "d15".U -> "h3F".U
//            )
//          )
          val mask = Cat(axLen, "b11".U(2.W))
          (addr & (~mask).asUInt) | ((addr + 4.U) & mask)
        },
        INCR -> (addr + 4.U)
      )
    )

  // ==========================================================================
  // SDRAM Main
  // ==========================================================================
  withClockAndReset(clock, reset) {
    // ========================================================================
    // AXI4 Request and Response
    // ========================================================================
    // ------------------------------------------------------------------------
    // AXI4 Request Wires and Registers
    // ------------------------------------------------------------------------
    /** AXI4 read and write request length */
    val req_len_q = RegInit(0.U(8.W))
    /** AXI4 read and write addr */
    val req_addr_q = RegInit(0.U(32.W))
    /** AXI4 write request enable */
    val req_wr_q = RegInit(false.B)
    /** AXI4 read request enable */
    val req_rd_q = RegInit(false.B)
    /** AXI4 read and write request id */
    val req_id_q = RegInit(0.U(4.W))
    /** AXI4 read and write burst type */
    val req_axburst_q = RegInit(0.U(2.W))
    /** AXI4 read and write burst length */
    val req_axlen_q = RegInit(0.U(8.W))
    /** AXI4 read and write priority, when ar or aw handshake happen, it will
      * flip value, ensure that when neither the read nor the write request is
      * in the hold state, if prio is high, write is executed, otherwise read is
      * executed.
      */
    val req_prio_q = RegInit(false.B)
    /** SDRAM write mask, it cotains both enable and mask functions. when it
      * don't equal 4'b0000, it represent write is enable. Since the data bit of
      * AXI4 is 32 and that of SDRAM is 16, write operation is divided into 2
      * steps, the lower 2 bit of mask are used for the first write (WRITE0),
      * and the upper 2 bit are used for the second write (WRITE1).
      */
    val ram_wr = WireInit(0.U(4.W))
    /** SDRAM read enalbe */
    val ram_rd = WireInit(0.U(1.W))
    /** SDRAM accept enable */
    val ram_accept = WireInit(false.B)

    dontTouch(req_len_q)
    dontTouch(req_addr_q)
    dontTouch(req_wr_q)
    dontTouch(req_rd_q)
    dontTouch(req_id_q)
    dontTouch(req_axburst_q)
    dontTouch(req_axlen_q)
    dontTouch(req_prio_q)
    dontTouch(ram_wr)
    dontTouch(ram_rd)
    dontTouch(ram_accept)

    /** When SDRAM mode is brust, let it perform read or write operation
      * continuously before request ends.
      */
    when((ram_wr =/= 0.U || ram_rd === 1.U) && ram_accept) {
      when(req_len_q === 0.U) {
        req_rd_q := false.B
        req_wr_q := false.B
      }
      req_addr_q := calculateAddressNext(req_addr_q, req_axburst_q, req_axlen_q)
      req_len_q := req_len_q - 1.U
    }

    /** When read or write handshake happens, update request registers. */
    when(axi.aw.valid && axi.aw.ready) {
      when(axi.w.valid && axi.w.ready) {
        req_wr_q := !axi.w.bits.last
        req_len_q := axi.aw.bits.len - 1.U
        req_id_q := axi.aw.bits.id
        req_axburst_q := axi.aw.bits.burst
        req_axlen_q := axi.aw.bits.len
        req_addr_q := calculateAddressNext(
          axi.aw.bits.addr,
          axi.aw.bits.burst,
          axi.aw.bits.len
        )
      }
      .otherwise {
        req_wr_q := true.B
        req_len_q := axi.aw.bits.len
        req_id_q := axi.aw.bits.id
        req_axburst_q := axi.aw.bits.burst
        req_axlen_q := axi.aw.bits.len
        req_addr_q := axi.aw.bits.addr
      }
      req_prio_q := !req_prio_q
    }
    .elsewhen(axi.ar.valid && axi.ar.ready) {
      req_rd_q := (axi.ar.bits.len =/= 0.U)
      req_len_q := axi.ar.bits.len - 1.U
      req_addr_q := calculateAddressNext(
        axi.ar.bits.addr,
        axi.ar.bits.burst,
        axi.ar.bits.len
      )
      req_id_q := axi.ar.bits.id
      req_axburst_q := axi.ar.bits.burst
      req_axlen_q := axi.ar.bits.len
      req_prio_q := !req_prio_q
    }

    /** AXI4 read request hold status */
    val req_hold_rd_q = RegInit(false.B)
    /** AXI4 write request hold status */
    val req_hold_wr_q = RegInit(false.B)

    dontTouch(req_hold_rd_q)
    dontTouch(req_hold_wr_q)

    /** When AXI4 read or write request is enable and cannot accept data, assert
      * corresponding hold status, otherwise deassert.
      */
    when(ram_rd === 1.U && !ram_accept) {
      req_hold_rd_q := true.B
    }
    .elsewhen(ram_accept) {
      req_hold_rd_q := false.B
    }
    when(ram_wr =/= 0.U && !ram_accept) {
      req_hold_wr_q := true.B
    }
    .elsewhen(ram_accept) {
      req_hold_wr_q := true.B
    }

    // ------------------------------------------------------------------------
    // AXI4 Request Tracking
    // ------------------------------------------------------------------------
    /** AXI4 request push enable */
    val req_push_w = ((ram_rd === 1.U) || (ram_wr =/= 0.U)) && ram_accept
    /** AXI4 request input control Req[5]: Request Status, 0 = Write, 1 = Read
      * Req[4]: AXI4 Address or Request Length Status, 0 = Length > 1, 1 =
      * Length equal 0 Req[3 : 0]: AXI4 Address ID
      */
    val req_in_r = RegInit(0.U(6.W))
    /** AXI4 request output valid enable */
    val req_out_valid_w = WireInit(false.B)
    /** AXI4 request out control */
    val req_out_w = WireInit(0.U(6.W))
    /** AXI4 response accept enable */
    val resp_accept_w = WireInit(false.B)
    /** AXI4 request FIFO accept enable */
    val req_fifo_accept_w = WireInit(false.B)
    /** SDRAM read data */
    val ram_read_data_w = WireInit(0.U(32.W))
    /** SDRAM ack enable */
    val ram_ack_w = WireInit(false.B)
    /** SDRAM accept enable */
    val ram_accept_w = WireInit(false.B)

    dontTouch(req_push_w)
    dontTouch(req_in_r)
    dontTouch(req_out_valid_w)
    dontTouch(req_out_w)
    dontTouch(resp_accept_w)
    dontTouch(req_fifo_accept_w)
    dontTouch(ram_read_data_w)
    dontTouch(ram_ack_w)
    dontTouch(ram_accept_w)

    when(axi.ar.valid && axi.ar.ready) {
      req_in_r := Cat(1.U(1.W), axi.ar.bits.len === 0.U, axi.ar.bits.id)
    }
    .elsewhen(axi.aw.valid && axi.aw.ready) {
      req_in_r := Cat(0.U(1.W), axi.aw.bits.len === 0.U, axi.aw.bits.id)
    }
    .otherwise {
      req_in_r := Cat(ram_rd, req_len_q === 0.U, req_id_q)
    }

    val u_requests: Instance[DW_fifo_s1_sf] = Instantiate(new DW_fifo_s1_sf(
      org.chipsalliance.dwbb.interface.DW_fifo_s1_sf.Parameter(
        width = req_in_r.getWidth,
        depth = 4,
        aeLevel = 1,
        afLevel = 1,
        errMode = "pointer_latched",
        rstMode = "async_with_mem"
      )
    ))
    u_requests.io.clk := clock
    u_requests.io.rst_n := !reset
    u_requests.io.push_req_n := !req_push_w
    u_requests.io.pop_req_n := !resp_accept_w
    u_requests.io.diag_n := true.B
    u_requests.io.data_in := req_in_r
    req_out_w := u_requests.io.data_out
    req_out_valid_w := u_requests.io.empty
    req_fifo_accept_w := u_requests.io.empty

    dontTouch(u_requests.io)

    val resp_is_write_w = Mux(req_out_valid_w, ~req_out_w(5), false.B)
    val resp_is_read_w = Mux(req_out_valid_w, req_out_w(5), false.B)
    val resp_is_last_w = req_out_w(4)
    val resp_id_w = req_out_w(3, 0)

    dontTouch(resp_is_write_w)
    dontTouch(resp_is_read_w)
    dontTouch(resp_is_last_w)
    dontTouch(resp_id_w)

    // ------------------------------------------------------------------------
    // AXI4 Response Buffering
    // ------------------------------------------------------------------------
    val resp_valid_w = WireInit(false.B)

    val u_response: Instance[DW_fifo_s1_sf] = Instantiate(new DW_fifo_s1_sf(
      org.chipsalliance.dwbb.interface.DW_fifo_s1_sf.Parameter(
        width = ram_read_data_w.getWidth,
        depth = 4,
        aeLevel = 1,
        afLevel = 1,
        errMode = "pointer_latched",
        rstMode = "async_with_mem"
      )
    ))
    u_response.io.clk := clock
    u_response.io.rst_n := !reset
    u_response.io.push_req_n := !ram_ack_w
    u_response.io.pop_req_n := !resp_accept_w
    u_response.io.diag_n := true.B
    u_response.io.data_in := ram_read_data_w
    axi.r.bits.data := u_response.io.data_out
    resp_valid_w := !u_response.io.empty

    dontTouch(u_response.io)

    // ------------------------------------------------------------------------
    // AXI4 Request
    // ------------------------------------------------------------------------
    val write_prio_w = (req_prio_q && !req_hold_rd_q) || req_hold_wr_q
    val read_prio_w = (!req_prio_q && !req_hold_wr_q) || req_hold_rd_q

    dontTouch(write_prio_w)
    dontTouch(read_prio_w)

    val write_active_w = (axi.aw.valid || req_wr_q) &&
      !req_rd_q &&
      req_fifo_accept_w &&
      (write_prio_w || req_wr_q || !axi.ar.valid)
    val read_active_w = (axi.ar.valid || req_rd_q) &&
      !req_wr_q &&
      req_fifo_accept_w &&
      (read_prio_w || req_rd_q || !axi.aw.valid)

    dontTouch(write_active_w)
    dontTouch(read_active_w)

    // awready：!req_wr_q写掩码不为空、req_fifo_accept_w请求FIFO为空
    axi.aw.ready := !req_wr_q && req_fifo_accept_w
    axi.w.ready  :=              req_fifo_accept_w
    // arready：!req_rd_q读完成-读握手之间、req_fifo_accept_w请求FIFO为空
    axi.ar.ready := !req_rd_q && req_fifo_accept_w
    dontTouch(axi.aw.ready)
    dontTouch(axi.w.ready)
    dontTouch(axi.ar.ready)

    val addr_w = Mux(
      req_wr_q || req_rd_q,
      req_addr_q,
      Mux(write_active_w, axi.aw.bits.addr, axi.ar.bits.addr)
    )

    dontTouch(addr_w)

    val wr_w = write_active_w && axi.w.valid
    val rd_w = read_active_w

    dontTouch(wr_w)
    dontTouch(rd_w)

    val ram_addr_w = addr_w
    val ram_write_data_w = axi.w.bits.data
    val ram_rd_w = rd_w
    val ram_wr_w = Mux(wr_w, axi.w.bits.strb, 0.U(4.W))

    dontTouch(ram_addr_w)
    dontTouch(ram_write_data_w)
    dontTouch(ram_rd_w)
    dontTouch(ram_wr_w)

    // ------------------------------------------------------------------------
    // AXI4 Response
    // ------------------------------------------------------------------------
    axi.b.valid := resp_valid_w && resp_is_write_w.asBool && resp_is_last_w
    axi.b.bits.resp := 0.U(2.W)
    axi.b.bits.id := resp_id_w
    axi.b.bits.user := 0.U

    dontTouch(axi.b.valid)
    dontTouch(axi.b.bits.resp)
    dontTouch(axi.b.bits.id)
    dontTouch(axi.b.bits.user)

    axi.r.valid := resp_valid_w && resp_is_read_w
    axi.r.bits.resp := 0.U(2.W)
    axi.r.bits.id := resp_id_w
    axi.r.bits.last := resp_is_last_w
    axi.r.bits.user := 0.U

    dontTouch(axi.r.valid)
    dontTouch(axi.r.bits.resp)
    dontTouch(axi.r.bits.id)
    dontTouch(axi.r.bits.last)
    dontTouch(axi.r.bits.user)

    resp_accept_w := (axi.r.valid && axi.r.ready) ||
      (axi.b.valid && axi.b.ready) ||
      (resp_valid_w && resp_is_write_w.asBool && !resp_is_last_w)

    dontTouch(resp_accept_w)

    // ========================================================================
    // SDRAM Controller
    // ========================================================================
    // ------------------------------------------------------------------------
    // SDRAM Parameters
    // ------------------------------------------------------------------------
    /** SDRAM External Parameters (User can customize them) */
    val SDRAM_MHZ = 50
    val SDRAM_ADDR_W = 24
    val SDRAM_COL_W = 9
    val SDRAM_READ_LATENCY = 2

    /** SDRAM Internal Parameters */
    /** SDRAM Data Width */
    val SDRAM_DATA_W = 16

    /** SDRAM Bank Width */
    val SDRAM_BANK_W = 2

    /** SDRAM Bank Number */
    val SDRAM_BANK_N = 1 << SDRAM_BANK_W

    /** SDRAM DQM Width */
    val SDRAM_DQM_W = 2

    /** SDRAM Row Width */
    val SDRAM_ROW_W = SDRAM_ADDR_W - SDRAM_COL_W - SDRAM_BANK_W

    /** SDRAM Refresh Counter */
    val SDRAM_REFRESH_CNT = 1 << SDRAM_ROW_W

    /** SDRAM INIT time (100us) */
    val SDRAM_TIME_INIT = 100000 / (1000 / SDRAM_MHZ)

    /** SDRAM Timing Parameters */
    /** Time per cycle */
    val SDRAM_CYCLE_NS = 1000 / SDRAM_MHZ

    /** Cycles between ACTIVE and READ/WRITE */
    val SDRAM_CYCLES_TRCD = (20 + (SDRAM_CYCLE_NS - 1)) / SDRAM_CYCLE_NS

    /** Cycles between PRECHARGE and ACTIVE */
    val SDRAM_CYCLES_TRP = (20 + (SDRAM_CYCLE_NS - 1)) / SDRAM_CYCLE_NS

    /** Cycles between REFRESH and OTHER COMMAND */
    val SDRAM_CYCLES_TRFC = (60 + (SDRAM_CYCLE_NS - 1)) / SDRAM_CYCLE_NS

    /** Cycles of REFRESH */
    val SDRAM_CYCLES_REFRESH = (64000 * SDRAM_MHZ) / SDRAM_REFRESH_CNT - 1

    /** The NO OPERATION (NOP) command is used to perform a NOP to the selected
      * device (CS# is LOW). This prevents unwanted commands from being
      * registered during idle or wait states. Operations already in progress
      * are not affected.
      */
    val CMD_NOP = "b0111".U(4.W)

    /** The mode registers are loaded via inputs A[n : 0] (where An is the most
      * significant address term), BA0, and BA1(see "Mode Register"). The LOAD
      * MODE REGISTER command can only be issued when all banks are idle and a
      * subsequent executable command cannot be issued until tMRD is met.
      */
    val CMD_LMR = "b0000".U(4.W)

    /** The ACTIVE command is used to activate a row in a particular bank for a
      * subsequent access. The value on the BA0, BA1 inputs selects the bank,
      * and the address provided selects the row. This row remains active for
      * accesses until a PRECHARGE command is issued to that bank. A PRECHARGE
      * command must be issued before opening a different row in the same bank.
      */
    val CMD_ACTIVE = "b0011".U(4.W)

    /** The READ command is used to initiate a burst read access to an active
      * row. The values on the BA0 and BA1 inputs select the bank; the address
      * provided selects the starting column location. The value on input A10
      * determines whether auto precharge is used. If auto precharge is
      * selected, the row being accessed is precharged at the end of the READ
      * burst; if auto precharge is not selected, the row remains open for
      * subsequent accesses. Read data appears on the DQ subject to the logic
      * level on the DQM inputs two clocks earlier. If a given DQM signal was
      * registered HIGH, the corresponding DQ will be High-Z two clocks later;
      * if the DQM signal was registered LOW, the DQ will provide valid data.
      */
    val CMD_READ = "b0101".U(4.W)

    /** The WRITE command is used to initiate a burst write access to an active
      * row. The values on the BA0 and BA1 inputs select the bank; the address
      * provided selects the starting column ocation. The value on input A10
      * determines whether auto precharge is used. If auto precharge is
      * selected, the row being accessed is precharged at the end of the write
      * burst; if auto precharge is not selected, the row remains open for
      * subsequent accesses. Input data appearing on the DQ is written to the
      * memory array, subject to the DQM input logic level appearing coincident
      * with the data. If a given DQM signal is registered LOW, the
      * corresponding data is written to memory; if the DQM signal is registered
      * HIGH, the corresponding data inputs are ignored and a WRITE is not
      * executed to that byte/column location.
      */
    val CMD_WRITE = "b0100".U(4.W)

    /** The PRECHARGE command is used to deactivate the open row in a particular
      * bank or the open row in all banks. The bank(s) will be available for a
      * subsequent row access a specified time (tRP) after the PRECHARGE command
      * is issued. Input A10 determines whether one or all banks are to be
      * precharged, and in the case where only one bank is precharged, inputs
      * BA0 and BA1 select the bank. Otherwise BA0 and BA1 are treated as "Don’t
      * Care." After a bank has been precharged, it is in the idle state and
      * must be activated prior to any READ or WRITE commands are issued to that
      * bank.
      */
    val CMD_PRECHARGE = "b0010".U(4.W)

    /** AUTO REFRESH is used during normal operation of the SDRAM and is
      * analogous to CAS#-BEFORE-RAS# (CBR) refresh in conventional DRAMs. This
      * command is nonpersistent, so it must be issued each time a refresh is
      * required. All active banks must be precharged prior to issuing an AUTO
      * REFRESH command. The AUTO REFRESH command should not be issued until the
      * minimum tRP has been met after the PRECHARGE command, as shown in
      * Bank/Row Activation.
      */
    val CMD_REFRESH = "b0001".U(4.W)

    /** Mode Register Definition (A[12 : 00]) A[12 : 10]: Reserved. A[09]: Write
      * Burst Mode. When A[09] = 0, the burst length programmed via A[02 : 00]
      * applies to both READ and WRITE bursts; when A[09] = 1, the programmed
      * burst length applies to READ bursts, but write accesses are
      * single-location (nonburst) accesses. 0 -> Programmed Burst Length 1 - >
      * Single Location Access A[08 : 07]: Operating Mode. The normal operating
      * mode is selected by setting A[07] and A[08] to zero; the other
      * combinations of values for A[07] and A[08] are reserved for future use.
      * Reserved states should not be used because unknown operation or
      * incompatibility with future versions may result. 00 -> Standard
      * Operation xx -> All other states reserved A[06 : 04]: CAS Latency. The
      * CAS latency (CL) is the delay, in clock cycles, between the registration
      * of a READ command and the availability of the output data. The latency
      * can be set to two or three clocks. 001 -> 1 010 -> 2 011 -> 3 A[03]:
      * Burst Type. Accesses within a given burst can be programmed to be either
      * sequential or interleaved; this is referred to as the burst type and is
      * selected via bit A[03]. 0 -> Sequential 1 -> Interleaved A[02 : 00]:
      * Burst Length. Read and write accesses to the device are burst oriented,
      * and the burst length (BL) is programmable. The burst length determines
      * the maximum number of column locations that can be accessed for a given
      * READ or WRITE command. Burst lengths of 1, 2, 4, 8, or continuous
      * locations are available for both the sequential and the interleaved
      * burst types, and a continuous page burst is available for the sequential
      * type. The continuous page burst is used in conjunction with the BURST
      * TERMINATE command to generate arbitrary burst lengths. 000 -> 1 001 -> 2
      * 010 -> 4 011 -> 8 111 -> Full Page(Only A[03] = 0, Burst Type is
      * Sequential]
      * -----------------------------------------------------------------------
      * SDRAM Mode: CAS Latency = 2, Burst Type = Sequential, Burst Length = 2
      */
    val MODE_REGISTER = Cat(
      "b000".U(3.W),
      0.U(1.W),
      0.U(2.W),
      "b010".U(3.W),
      0.U(1.W),
      "b001".U(3.W)
    )

    /** SDRAM State Machines */
    val STATE_W = 4
    val STATE_INIT = 0.U(STATE_W.W)
    val STATE_DELAY = 1.U(STATE_W.W)
    val STATE_IDLE = 2.U(STATE_W.W)
    val STATE_ACTIVATE = 3.U(STATE_W.W)
    val STATE_READ = 4.U(STATE_W.W)
    val STATE_READ_WAIT = 5.U(STATE_W.W)
    val STATE_WRITE0 = 6.U(STATE_W.W)
    val STATE_WRITE1 = 7.U(STATE_W.W)
    val STATE_PRECHARGE = 8.U(STATE_W.W)
    val STATE_REFRESH = 9.U(STATE_W.W)

    /** A10 is special bit in A[12 : 00], when current state is PRECHARGE, if
      * A10 is 1, it represent all 4 banks will be precharged; When current
      * state is READ or WRITE, if A10 is 1, a precharge of the bank/row that is
      * addressed with the READ or WRITE command is automatically performed upon
      * completion of the READ or WRITE burst, except in the continuous page
      * burst mode where auto precharge does not apply.
      */
    val BIT_AUTO_PRECHARGE = 10
    val BIT_ALL_BANKS = 10

    // ------------------------------------------------------------------------
    // SDRAM Wires and Registers
    // ------------------------------------------------------------------------
    /** SDRAM Read or Write request */
    val ram_req_w = (ram_wr_w =/= 0.U) || ram_rd_w
    /** SDRAM Command */
    val command_q = RegInit(CMD_NOP)
    /** SDRAM Row Address */
    val addr_q = RegInit(0.U(SDRAM_ROW_W.W))
    /** SDRAM Data */
    val data_q = RegInit(0.U(SDRAM_DATA_W.W))
    /** SDRAM Read Enable */
    val data_rd_en_q = RegInit(true.B)
    /** SDRAM DQM */
    val dqm_q = RegInit(0.U(SDRAM_DQM_W.W))
    /** SDRAM Clock Enable */
    val cke_q = RegInit(false.B)
    /** SDRAM Bank Address */
    val bank_q = RegInit(0.U(SDRAM_BANK_W.W))
    /** During READ and WRITE command, use buffer to receive stable data. */
    /** SDRAM Data Buffer */
    val data_buffer_q = RegInit(0.U(SDRAM_DATA_W.W))
    /** SDRAM DQM Buffer */
    val dqm_buffer_q = RegInit(0.U(SDRAM_DQM_W.W))
    /** SDRAM Input Data */
    val sdram_data_in_w = WireInit(0.U(SDRAM_DATA_W.W))
    /** SDRAM Refresh Enable */
    val refresh_q = RegInit(false.B)
    /** SDRAM Open Row Enable (Every bit represents different bank) */
    val row_open_q = RegInit(0.U(SDRAM_BANK_N.W))
    /** SDRAM Active Row Enable */
    val active_row_q = VecInit.fill(SDRAM_BANK_N)(0.U(SDRAM_BANK_W.W))
    /** Current State */
    val state_q = RegInit(STATE_INIT)
    /** Next State */
    val next_state_r = RegInit(0.U(STATE_W.W))
    /** Target State (Next). When current state is ACTIVATE, use it to indicate
      * whether next state is READ or WRITE. When current state is PRECHARGE,
      * REFRESH priority is higher than ACTIVE, if target state is REFRESH, let
      * next state is REFRESH, otherwise is ACTIVATE.
      */
    val target_state_r = RegInit(0.U(STATE_W.W))
    /** Target State (Current) */
    val target_state_q = RegInit(STATE_IDLE)
    /** Deleay State (Used for all delay operations) */
    val delay_state_q = RegInit(STATE_IDLE)

    dontTouch(ram_req_w)
    dontTouch(command_q)
    dontTouch(addr_q)
    dontTouch(data_q)
    dontTouch(data_rd_en_q)
    dontTouch(dqm_q)
    dontTouch(cke_q)
    dontTouch(bank_q)
    dontTouch(data_buffer_q)
    dontTouch(dqm_buffer_q)
    dontTouch(sdram_data_in_w)
    dontTouch(refresh_q)
    dontTouch(row_open_q)
    dontTouch(active_row_q)
    dontTouch(state_q)
    dontTouch(next_state_r)
    dontTouch(target_state_r)
    dontTouch(target_state_q)
    dontTouch(delay_state_q)

    /** SDRAM Column Address (Current) */
    val addr_col_w = Cat(
      Fill(SDRAM_ROW_W - SDRAM_COL_W, 0.U(1.W)),
      ram_addr_w(SDRAM_COL_W, 2),
      0.U(1.W)
    )
    /** SDRAM Row Address (Current) */
    val addr_row_w = ram_addr_w(SDRAM_ADDR_W, SDRAM_COL_W + 2 + 1)
    /** SDRAM Bank Address (Current) */
    val addr_bank_w = ram_addr_w(SDRAM_COL_W + 2, SDRAM_COL_W + 2 - 1)

    dontTouch(addr_col_w)
    dontTouch(addr_row_w)
    dontTouch(addr_bank_w)

    // ------------------------------------------------------------------------
    // SDRAM State Machine
    // ------------------------------------------------------------------------
    /** Todo: Use Decode api and Mux1H to refactor state machine */
    /* SDRAM State Truth Table
     * +------------+----------------------+---------------------------------------------------+
     * |   Current  | CS#, RAS#, CAS#, WE# | Action                                            |
     * +------------+----------------------+---------------------------------------------------+
     * |      *     |       1XXX/0111      | NOP                                               |
     * +------------+----------------------+---------------------------------------------------+
     * |            |         0011         | ACTIVE (select and activate row)                  |
     * |            +----------------------+---------------------------------------------------+
     * |            |         0001         | AUTO REFRESH                                      |
     * |    Idle    +----------------------+---------------------------------------------------+
     * |            |         0000         | LOAD MODE REGISTER                                |
     * |            +----------------------+---------------------------------------------------+
     * |            |         0010         | PRECHARGE                                         |
     * +------------+----------------------+---------------------------------------------------+
     * |            |         0101         | READ (select column and start READ burst)         |
     * |            +----------------------+---------------------------------------------------+
     * | Row active |         0100         | WRITE (select column and start WRITE burst)       |
     * |            +----------------------+---------------------------------------------------+
     * |            |         0010         | PRECHARGE (deactivate row in bank or banks)       |
     * +------------+----------------------+---------------------------------------------------+
     * |            |         0101         | READ (select column and start new READ burst)     |
     * |            +----------------------+---------------------------------------------------+
     * |            |         0100         | WRITE (select column and start WRITE burst)       |
     * |    Read    +----------------------+---------------------------------------------------+
     * |            |         0010         | PRECHARGE (truncate READ burst, start PRECHARGE)  |
     * |            +----------------------+---------------------------------------------------+
     * |            |         0110         | BURST TERMINATE                                   |
     * +------------+----------------------+---------------------------------------------------+
     * |            |         0101         | READ (select column and start new READ burst)     |
     * |            +----------------------+---------------------------------------------------+
     * |            |         0100         | WRITE (select column and start WRITE burst)       |
     * |    Write   +----------------------+---------------------------------------------------+
     * |            |         0010         | PRECHARGE (truncate WRITE burst, start PRECHARGE) |
     * |            +----------------------+---------------------------------------------------+
     * |            |         0110         | BURST TERMINATE                                   |
     * +------------+----------------------+---------------------------------------------------+
     */
    // next_state_r := state_q
    target_state_r := target_state_q

    switch(state_q) {
      /** Next State is IDLE, when the number of refresh is reached. */
      is(STATE_INIT) {
        when(refresh_q) {
          next_state_r := STATE_IDLE
        }
      }
      /** IDLE is the most important STATE, it determine which state to jump to
        * next based on conditions such as refresh counter, request enable, and
        * row open, etc.
        */
      is(STATE_IDLE) {
        when(refresh_q) {
          /** Close open rows, then refresh */
          when(row_open_q =/= 0.U) {
            next_state_r := STATE_PRECHARGE
          }
          .otherwise {
            next_state_r := STATE_REFRESH
          }
          target_state_r := STATE_REFRESH
        }
        .elsewhen(ram_req_w) {
          /** Open row and active row hit at the same time */
          when(
            row_open_q(addr_bank_w) &&
              (addr_row_w === active_row_q(addr_bank_w))
          ) {
            when(!ram_rd_w) {
              next_state_r := STATE_WRITE0
            }.otherwise {
              next_state_r := STATE_READ
            }
          }
          /** Open row miss, close it and open new row */
          .elsewhen(row_open_q(addr_bank_w)) {
            next_state_r := STATE_PRECHARGE
            when(!ram_rd_w) {
              target_state_r := STATE_WRITE0
            }.otherwise {
              target_state_r := STATE_READ
            }
          }
          /** No open row, open row */
          .otherwise {
            next_state_r := STATE_ACTIVATE
            when(!ram_rd_w) {
              target_state_r := STATE_WRITE0
            }.otherwise {
              target_state_r := STATE_READ
            }
          }
        }
      }
      /** Before executing READ or WRITE, ACTIVATE must be executed, so by
        * getting the value of target state, state machine can jump to the
        * corresponding READ or WRITE state.
        */
      is(STATE_ACTIVATE) {
        next_state_r := target_state_r
      }
      /** Next State is READ_WAIT */
      is(STATE_READ) {
        next_state_r := STATE_READ_WAIT
      }
      /** Default next state is IDLE, but if another READ request with no
        * refresh come, and its bank hits and row is active, next state is still
        * READ.
        */
      is(STATE_READ_WAIT) {
        next_state_r := STATE_IDLE
        when(!refresh_q && ram_req_w && ram_rd_w) {
          when(
            row_open_q(addr_bank_w) &&
              (addr_row_w === active_row_q(addr_bank_w))
          ) {
            next_state_r := STATE_READ
          }
        }
      }
      /** Next State is WRITE1 */
      is(STATE_WRITE0) {
        next_state_r := STATE_WRITE1
      }
      /** Default next state is IDLE, but if another WRITE request with no
        * refresh come, and its bank hits and row is active, next state is still
        * WRITE.
        */
      is(STATE_WRITE1) {
        next_state_r := STATE_IDLE
        when(!refresh_q && ram_req_w && ram_wr_w =/= 0.U) {
          when(
            row_open_q(addr_bank_w) &&
              (addr_row_w === active_row_q(addr_bank_w))
          ) {
            next_state_r := STATE_WRITE0
          }
        }
      }
      /** REFRESH priority is higher than ACTIVE, if target state is REFRESH,
        * let next state is REFRESH, otherwise is ACTIVATE.
        */
      is(STATE_PRECHARGE) {
        when(target_state_r === STATE_REFRESH) {
          next_state_r := STATE_REFRESH
        }.otherwise {
          next_state_r := STATE_ACTIVATE
        }
      }
      /** Next State is IDLE */
      is(STATE_REFRESH) {
        next_state_r := STATE_IDLE
      }
      is(STATE_DELAY) {
        next_state_r := delay_state_q
      }
    }

    // ------------------------------------------------------------------------
    // SDRAM Delay Operation
    // ------------------------------------------------------------------------
    val DELAY_W = 4

    /** SDRAM Delay (Current) */
    val delay_q = RegInit(0.U(DELAY_W.W))
    /** SDRAM Delay (Next) */
    val delay_r = RegInit(0.U(DELAY_W.W))

    dontTouch(delay_q)
    dontTouch(delay_r)

    delay_r := 0.U(DELAY_W.W)

    switch(state_q) {
      is(STATE_ACTIVATE) {
        delay_r := SDRAM_CYCLES_TRCD.asUInt
      }
      is(STATE_READ_WAIT) {
        delay_r := SDRAM_READ_LATENCY.asUInt

        /** When READ request come, open row and active row hit at the same
          * time, don't delay.
          */
        when(!refresh_q && ram_req_w && ram_rd_w) {
          when(
            row_open_q(addr_bank_w) &&
              (addr_row_w === active_row_q(addr_bank_w))
          ) {
            delay_r := 0.U(DELAY_W.W)
          }
        }
      }
      is(STATE_PRECHARGE) {
        delay_r := SDRAM_CYCLES_TRP.asUInt
      }
      is(STATE_REFRESH) {
        delay_r := SDRAM_CYCLES_TRFC.asUInt
      }
      is(STATE_DELAY) {
        delay_r := delay_q - 1.U(DELAY_W.W)
      }
    }

    /** Record target state */
    target_state_q := target_state_r

    /** Record delayed state */
    when (state_q =/= STATE_DELAY && delay_r =/= 0.U(DELAY_W.W)) {
      delay_state_q := next_state_r
    }

    /** Update actual state */
    when (delay_r =/= 0.U(DELAY_W.W)) {
      state_q := STATE_DELAY
    }
    .otherwise {
      state_q := next_state_r;
    }

    /** Record delay state */
    delay_q := delay_r

    // ------------------------------------------------------------------------
    // SDRAM Refresh Operation
    // ------------------------------------------------------------------------
    /** SDRAM Refresh Counter Width */
    val REFRESH_CNT_W = 17

    /** Make ensure INIT is complete */
    val refresh_timer_q = RegInit((SDRAM_TIME_INIT + 100).U(REFRESH_CNT_W.W))

    dontTouch(refresh_timer_q)

    when(refresh_timer_q === 0.U(REFRESH_CNT_W.W)) {
      refresh_timer_q := SDRAM_CYCLES_REFRESH.asUInt
    }
    .otherwise {
      refresh_timer_q := refresh_timer_q - 1.U
    }

    when(refresh_timer_q === 0.U(REFRESH_CNT_W.W)) {
      refresh_q := true.B
    }
    .otherwise {
      refresh_q := false.B
    }

    // ------------------------------------------------------------------------
    // SDRAM Input Sampling
    // ------------------------------------------------------------------------
    /** Use 2-level register to implement input data samping, ensure input data
      * is obtained correctly.
      */
    val sample_data0_q = RegInit(0.U(SDRAM_DATA_W.W))
    val sample_data_q = RegInit(0.U(SDRAM_DATA_W.W))

    dontTouch(sample_data0_q)
    dontTouch(sample_data_q)

    sample_data0_q := sdram_data_in_w
    sample_data_q  := sample_data0_q

    // ------------------------------------------------------------------------
    // SDRAM Command Output
    // ------------------------------------------------------------------------
    command_q := CMD_NOP
    addr_q := 0.U(SDRAM_ROW_W.W)
    bank_q := 0.U(SDRAM_BANK_W.W)
    data_rd_en_q := true.B

    switch(state_q) {
      is(STATE_INIT) {
        when(refresh_timer_q === 50.U) {
          cke_q := true.B
        }.elsewhen(refresh_timer_q === 40.U) {
          command_q := CMD_PRECHARGE
          // TODO: fix me: addr_q(BIT_ALL_BANKS) := 1.U(1.W)
          addr_q := Cat(
            addr_q(SDRAM_ROW_W - 1, BIT_ALL_BANKS + 1),
            1.U,
            addr_q(BIT_ALL_BANKS - 1, 0)
          )
        }.elsewhen(refresh_timer_q === 20.U || refresh_timer_q === 30.U) {
          command_q := CMD_REFRESH
        }.elsewhen(refresh_timer_q === 10.U) {
          command_q := CMD_LMR
          addr_q := MODE_REGISTER
        }.otherwise {
          command_q := CMD_NOP
          addr_q := 0.U(SDRAM_ROW_W.W)
          bank_q := 0.U(SDRAM_BANK_W.W)
        }
      }
      is(STATE_ACTIVATE) {
        command_q := CMD_ACTIVE
        addr_q := addr_row_w
        bank_q := addr_bank_w

        active_row_q(addr_bank_w) := addr_row_w
        // TODO: fix me: row_open_q(addr_bank_w) := 1.U(1.W)
        row_open_q := MuxLookup(addr_bank_w, row_open_q)(
          Seq(
            0.U -> Cat(row_open_q(SDRAM_BANK_N - 1, 1), 1.U),
            1.U -> Cat(row_open_q(SDRAM_BANK_N - 1, 2), 1.U, row_open_q(0)),
            2.U -> Cat(
              row_open_q(SDRAM_BANK_N - 1, 3),
              1.U,
              row_open_q(SDRAM_BANK_N - 3, 0)
            ),
            3.U -> Cat(1.U, row_open_q(SDRAM_BANK_N - 2, 0))
          )
        )
      }
      is(STATE_PRECHARGE) {
        command_q := CMD_PRECHARGE
        when(target_state_r === STATE_REFRESH) {
          // TODO: fix me: addr_q(BIT_ALL_BANKS) := 1.U(1.W)
          /** Precharge all banks */
          addr_q := Cat(
            addr_q(SDRAM_ROW_W - 1, BIT_ALL_BANKS + 1),
            1.U,
            addr_q(BIT_ALL_BANKS - 1, 0)
          )

          /** Close all open rows */
          row_open_q := 0.U(SDRAM_BANK_N.W)
        }
        .otherwise {
          // TODO: fix me: addr_q(BIT_ALL_BANKS) := 0.U(1.W)
          /** Precharge specific bank */
          addr_q := Cat(
            addr_q(SDRAM_ROW_W - 1, BIT_ALL_BANKS + 1),
            0.U,
            addr_q(BIT_ALL_BANKS - 1, 0)
          )
          bank_q := addr_bank_w
          // TODO: fix me: row_open_q(addr_bank_w) := 0.U(1.W)
          /** Close specific open row */
          row_open_q := MuxLookup(addr_bank_w, row_open_q)(
            Seq(
              0.U -> Cat(row_open_q(SDRAM_BANK_N - 1, 1), 0.U),
              1.U -> Cat(row_open_q(SDRAM_BANK_N - 1, 2), 0.U, row_open_q(0)),
              2.U -> Cat(
                row_open_q(SDRAM_BANK_N - 1, 3),
                0.U,
                row_open_q(SDRAM_BANK_N - 3, 0)
              ),
              3.U -> Cat(1.U, row_open_q(SDRAM_BANK_N - 2, 0))
            )
          )
        }
      }
      is(STATE_REFRESH) {
        command_q := CMD_REFRESH
        addr_q := 0.U(SDRAM_ROW_W.W)
        bank_q := 0.U(SDRAM_BANK_W.W)
      }
      is(STATE_READ) {
        command_q := CMD_READ
        addr_q := addr_col_w
        bank_q := addr_bank_w

        // TODO: fix me: addr_q(BIT_AUTO_PRECHARGE) := 0.U(1.W)
        /** Disable AUTO PRECHARGE (auto close of row) */
        addr_q := Cat(
          addr_q(SDRAM_ROW_W - 1, BIT_AUTO_PRECHARGE + 1),
          0.U,
          addr_q(BIT_AUTO_PRECHARGE - 1, 0)
        )
        dqm_q := 0.U(SDRAM_DQM_W.W)
      }
      is(STATE_WRITE0) {
        command_q := CMD_WRITE
        addr_q := addr_col_w
        bank_q := addr_bank_w
        data_q := ram_write_data_w(15, 0)

        // TODO: fix me: addr_q(BIT_AUTO_PRECHARGE) := 0.U(1.W)
        /** Disable AUTO PRECHARGE (auto close of row) */
        addr_q := Cat(
          addr_q(SDRAM_ROW_W - 1, BIT_AUTO_PRECHARGE + 1),
          0.U,
          addr_q(BIT_AUTO_PRECHARGE - 1, 0)
        )

        /** Because data width is 16 bit, only 2 bits are needed to implement
          * byte mask. Low effective.
          */
        dqm_q := ~ram_wr_w(1, 0)
        dqm_buffer_q := ~ram_wr_w(3, 2)

        data_rd_en_q := false.B
      }
      is(STATE_WRITE1) {
        command_q := CMD_NOP
        data_q := data_buffer_q

        // TODO: fix me: addr_q(BIT_AUTO_PRECHARGE) := 0.U(1.W)
        /** Disable AUTO PRECHARGE (auto close of row) */
        addr_q := Cat(
          addr_q(SDRAM_ROW_W - 1, BIT_AUTO_PRECHARGE + 1),
          0.U,
          addr_q(BIT_AUTO_PRECHARGE - 1, 0)
        )
        dqm_q := dqm_buffer_q
      }
    }

    // ------------------------------------------------------------------------
    // SDRAM READ State Record
    // ------------------------------------------------------------------------
    /** The length of register represents READ Latency, each bit represents
      * whether the controller state is READ in different cycle.
      */
    val rd_q = RegInit(0.U((SDRAM_READ_LATENCY + 2).W))

    dontTouch(rd_q)

    rd_q := Cat(rd_q(SDRAM_READ_LATENCY, 0), state_q === STATE_READ)

    // ------------------------------------------------------------------------
    // SDRAM Data Buffer
    // ------------------------------------------------------------------------
    /** Because SDRAM data width is 16bit, it is neccessary to store high 16-bit
      * data to buffer temporarily.
      */
    when(state_q === STATE_WRITE0) {
      data_buffer_q := ram_write_data_w(31, 16)
    }
    /** Judge state in the next cycle after delay, if it is READ, then store
      * input sampling to buffer.
      */
    .elsewhen(rd_q(SDRAM_READ_LATENCY + 1)) {
      data_buffer_q := sample_data_q
    }
    ram_read_data_w := Cat(sample_data_q, data_buffer_q)

    // ------------------------------------------------------------------------
    // SDRAM ACK
    // ------------------------------------------------------------------------
    /** Pulling signal high indicates that READ or WRITE is complete. */
    val ack_q = RegInit(false.B)

    dontTouch(ack_q)

    when(state_q === STATE_WRITE1) {
      ack_q := true.B
    }
    .elsewhen(rd_q(SDRAM_READ_LATENCY + 1)) {
      ack_q := true.B
    }
    .otherwise {
      ack_q := false.B
    }

    ram_ack_w := ack_q

    /** Pulling signal high indicates that AXI4 read address, write address,
      * write data requests can be accepted for SDRAM.
      */
    ram_accept_w := (state_q === STATE_READ || state_q === STATE_WRITE0)
    dontTouch(ram_accept_w)

    // ------------------------------------------------------------------------
    // SDRAM Innput / Output
    // ------------------------------------------------------------------------
    // TODO: this is forbidden in RTL, use CTS blackbox instead.
    sdram.ck.foreach(_ := (~clock.asBool).asBool.asClock)
    sdram.cke := cke_q
    sdram.cs := command_q(3)
    sdram.ras := command_q(2)
    sdram.cas := command_q(1)
    sdram.we := command_q(0)
    sdram.dqm := dqm_q
    sdram.ba := bank_q
    sdram.a := addr_q
    sdram.dqDir := ~data_rd_en_q
    sdram.dqo := data_q

    sdram_data_in_w := sdram.dqi

    ram_wr := ram_wr_w
    ram_rd := ram_rd_w
    ram_accept := ram_accept_w
  }
}
