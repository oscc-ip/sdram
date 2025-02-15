package SdramController;
import SdramPhy :: *;
import OuterPhy :: *;
import ConstIfc :: *;
import StmtFSM :: *;
import FIFOF :: *;
import Vector :: *;
import Gearbox :: *;
import DefaultValue :: *;
import BlueAXI :: *;

interface SdramControllerIfc;
    interface AxiIfc axi;
    interface SdramIfc sdram;
endinterface

(* synthesize *)
module mkSdramController(SdramControllerIfc);
    let sdramPhy <- mkSdramPhy;
    let outerPhy <- mkOuterPhy;
    let defaultClock <- exposeCurrentClock;
    let defaultReset <- exposeCurrentReset;

    Reg#(StateEnum) state[4] <- mkCReg(4, PowerUp);
    Reg#(StateEnum) backState <- mkRegU;

    Reg#(Bit#(32)) refreshCount <- mkRegU;
    Reg#(Bit#(32)) prechargeCount <- mkReg(0);
    Reg#(Maybe#(Bit#(15))) currentActive <- mkReg(Invalid);
    Reg#(Maybe#(Bit#(AxiAddrWidth))) currentAddr[2] <- mkCReg(2, Invalid);
    Reg#(Maybe#(AddrReqType)) currentReq[2] <- mkCReg(2, Invalid);
    Wire#(Maybe#(RStatus)) rStatus <- mkDWire(Invalid);

    Reg#(Bit#(32)) i <- mkRegU;

    function Bit#(AxiAddrWidth) alignAddr(Bit#(AxiAddrWidth) currentAddr, AXI4_BurstSize burstSize);
        Bit#(AxiAddrWidth) ret = currentAddr;
        case (burstSize) matches
            B2: ret[0] = 0;
            B4: ret[1: 0] = 0;
            B8: ret[2: 0] = 0;
            B16: ret[3: 0] = 0;
            B32: ret[4: 0] = 0;
            B64: ret[5: 0] = 0;
            B128: ret[6: 0] = 0;
        endcase
        return ret;
    endfunction

    function Bit#(AxiAddrWidth) nextAddr(Bit#(AxiAddrWidth) currentAddr, AddrReqType req);
        case (req.burst_type) matches
            tagged FIXED:
                return currentAddr;
            tagged INCR: begin
                Bit#(AxiAddrWidth) alignedAddr = alignAddr(currentAddr, req.burst_size);
                return alignedAddr + (1 << pack(req.burst_size));
            end
            tagged WRAP: begin
                Bit#(AxiAddrWidth) wrapMask = (case(req.burst_length) matches
                    'd1: return (1<<(pack(req.burst_size) + 1));
                    'd3: return (1<<(pack(req.burst_size) + 2));
                    'd7: return (1<<(pack(req.burst_size) + 3));
                    'd15: return (1<<(pack(req.burst_size) + 4));
                endcase) - 1;
                Bit#(AxiAddrWidth) retAddr = currentAddr + (1 << pack(req.burst_size));
                return (currentAddr & ~wrapMask) | (retAddr & wrapMask);
            end
        endcase
    endfunction

    function UInt#(16) calcNeedCount(Bool isCurrentRead, Bit#(AxiAddrWidth) addr, AXI4_BurstSize burst_size, AXI4_BurstType burst_type, UInt#(8) burst_length);
        let crossBoundary = addr[0] == 1;
        let needCount = (isCurrentRead ? (case (burst_size) matches
            B1: begin
                if (burst_length == 0)
                    return 1;
                else
                    return ((extend(burst_length) + 2) >> 1 + (crossBoundary ? 1 : 0));
            end
            B2: begin
                return ((extend(burst_length) + 1) + (crossBoundary ? 1 : 0));
            end
            B4: begin
                return ((extend(burst_length) + 1) << 1) + (crossBoundary ? 1 : 0);
            end
        endcase) : ((extend(burst_length) + 1) << 1));
        return needCount;
    endfunction

    let powerUpFsm <- mkFSM( seq
        // $display("Nop 20_000 cycles...");
        delay(20_000);
        // $display("Precharge all banks...");
        sdramPhy.write(Cmd_Precharge(Invalid));
        delay(3);
        for (i <= 0; i < 8; i <= i + 1) seq
            // $display("Auto Refresh...");
            sdramPhy.write(Cmd_Refresh(False));
            delay(11);
        endseq
        // $display("Load mode...");
        sdramPhy.write(Cmd_ModeLoad);
    endseq );

    let refreshFsm <- mkFSM( seq
        sdramPhy.write(Cmd_Refresh(True));
        delay(11);
        sdramPhy.write(Cmd_Refresh(True));
        delay(11);
    endseq );

    let prechargeFsm <- mkFSM( seq
        if (prechargeCount < 8) seq
            delay(8 - prechargeCount);
        endseq
        sdramPhy.write(Cmd_Precharge(Invalid));
        delay(11);
        sdramPhy.write(Cmd_Refresh(True));
        delay(11);
    endseq );

    Reg#(Bool) isCurrentRead <- mkReg(False);
    Reg#(Bool) hasInitiated <- mkReg(False);
    Reg#(Bool) hasRefreshed <- mkReg(False);
    Reg#(Bool) hasPrecharged <- mkReg(False);
    Reg#(UInt#(4)) beforePrechargeCount[2] <- mkCReg(2, 0);
    Reg#(UInt#(4)) beforeActCount[2] <- mkCReg(2, 0);

    rule powerUp if (!hasInitiated && state[0] == PowerUp);
        powerUpFsm.start;
        hasInitiated <= True;
    endrule

    rule powerUpDone if (hasInitiated && state[0] == PowerUp);
        powerUpFsm.waitTillDone;
        state[0] <= Idle;
        refreshCount <= 20_000;
    endrule

    rule refresh if (!hasRefreshed && state[0] == Refresh);
        refreshFsm.start;
        hasRefreshed <= True;
    endrule

    rule refreshDone if (hasRefreshed && state[0] == Refresh);
        refreshFsm.waitTillDone;
        hasRefreshed <= False;
        state[0] <= backState;
        refreshCount <= 20_000;
    endrule

    rule prechargeAll if (!hasPrecharged && state[0] == Precharge);
        if (beforePrechargeCount[0] == 0) begin
            prechargeFsm.start;
            hasPrecharged <= True;
            currentActive <= Invalid;
        end
    endrule

    rule prechargeAllDone if (hasPrecharged && state[0] == Precharge);
        prechargeFsm.waitTillDone;
        hasPrecharged <= False;
        state[0] <= backState;
        prechargeCount <= 0;
        if (backState == Act) begin
            beforeActCount[1] <= 8;
        end
    endrule

    rule prechargeCountIncrease if (isValid(currentActive) && state[0] != Precharge);
        prechargeCount <= prechargeCount + 1;
    endrule

    rule refreshCountDecrease(state[0] != Refresh && state[0] != PowerUp);
        refreshCount <= refreshCount - 1;
    endrule

    Reg#(UInt#(8)) needCount <- mkReg(0);

    rule idle if (state[1] == Idle);
        let addrReq = currentReq[1];
        if(isValid(currentActive) && (prechargeCount >= 20_000 - 5 || refreshCount < 24)) begin
            backState <= Idle;
            state[1] <= Precharge;
        end else if (refreshCount < 24) begin
            backState <= Idle;
            state[1] <= Refresh;
        end else begin
            if(!isValid(addrReq)) begin
                if (outerPhy.awValid && (isCurrentRead || (!isCurrentRead && !outerPhy.arValid))) begin
                    let d <- outerPhy.readAwReq;
                    addrReq = tagged Valid AddrReqType {id: d.id, addr: d.addr, burst_length: d.burst_length, burst_size: d.burst_size, burst_type: d.burst_type};
                    isCurrentRead <= False;
                end else if (outerPhy.arValid) begin
                    let d <- outerPhy.readArReq;
                    addrReq = tagged Valid AddrReqType {id: d.id, addr: d.addr, burst_length: d.burst_length, burst_size: d.burst_size, burst_type: d.burst_type};
                    isCurrentRead <= True;
                end
            end
            if (isValid(addrReq)) begin
                currentReq[1] <= addrReq;
                currentAddr[1] <= tagged Valid fromMaybe(?, addrReq).addr;
                state[1] <= Act;
            end
        end
    endrule

    Reg#(Bit#(32)) delayCount <- mkRegU;

    /*
    Row: [24:12], Bank: [11:10], Col: [9:1], [0]
    */
    rule act if (state[2] == Act);
        let nextState = Idle;
        if (isValid(currentActive) && isValid(currentAddr[1])) begin
            if (fromMaybe(?, currentAddr[1])[24:10] == fromMaybe(?, currentActive)) begin
                if (needCount == 0) begin
                    needCount <= fromMaybe(?, currentReq[1]).burst_length;
                end
                if (isCurrentRead) begin
                    if (outerPhy.rRespNotFull) begin
                        nextState = StartRead;
                    end
                end else begin
                    nextState = StartWrite;
                end
            end else begin
                nextState = Precharge;
                backState <= Act;
            end
        end else if (beforeActCount[1] == 0) begin
            sdramPhy.write(tagged Cmd_Activate {row: fromMaybe(?, currentAddr[1])[24:12], bank: fromMaybe(?, currentAddr[1])[11:10]});
            currentActive <= tagged Valid fromMaybe(?, currentAddr[1])[24:10];
            nextState = Delay;
            delayCount <= 3;
            backState <= Act;
        end
        state[2] <= nextState;
    endrule

    rule delay if (state[0] == Delay);
        /*
        current & next cmd will use 2 cycles.
        */
        if (delayCount > 2) begin
            delayCount <= delayCount - 1;
        end else begin
            state[0] <= backState;
        end
    endrule

    Reg#(Bool) needSplitRead <- mkReg(False);

    rule startReadOrWaitRead if (state[0] == StartRead || state[0] == WaitRead);
        let nextState = WaitRead;
        if (outerPhy.rRespNotFull) begin
            let col = fromMaybe(?, currentAddr[0])[9:1] + (needSplitRead ? 1: 0);
            let nextAddrTmp = nextAddr(fromMaybe(?, currentAddr[0]), fromMaybe(?, currentReq[0]));
            let nextCol = nextAddrTmp[9:1];
            let nextAddrTmp2 = nextAddr(nextAddrTmp, fromMaybe(?, currentReq[0]));
            let nextCol2 = nextAddrTmp2[9:1];
            let nextCurrentAddr = tagged Valid nextAddrTmp;
            let decNeedCount = 1;
            if (state[0] == StartRead) begin
                sdramPhy.write(Cmd_Read(col));
            end
            case (fromMaybe(?, currentReq[0]).burst_size) matches
                B1:
                begin
                    rStatus <= tagged Valid RStatus {
                        offset: col[0],
                        replicate: nextCol == col,
                        last: needCount == 1,
                        burst_size: fromMaybe(?, currentReq[0]).burst_size,
                        id: fromMaybe(?, currentReq[0]).id
                    };
                    if (nextCol == col) begin
                        decNeedCount = 2;
                        nextCurrentAddr = tagged Valid nextAddrTmp2;
                    end
                    if ((nextCol != col && nextCol != col + 1) || (nextCol == col && nextCol2 != col + 1)) begin
                        // todo: do we need to stop before a new read?
                        nextState = StartRead;
                    end
                end
                B2:
                begin
                    rStatus <= tagged Valid RStatus {
                        offset: col[0],
                        replicate: False,
                        last: needCount == 1,
                        burst_size: fromMaybe(?, currentReq[0]).burst_size,
                        id: fromMaybe(?, currentReq[0]).id
                    };
                    if (nextCol != col + 1) begin
                        nextState = StartRead;
                    end
                end
                B4:
                begin
                    if (!needSplitRead && col[0] != 1) begin
                        // we need 2 cycles to read
                        needSplitRead <= True;
                        nextCurrentAddr = currentAddr[0];
                        decNeedCount = 0;
                    end else begin
                        needSplitRead <= False;
                    end
                    rStatus <= tagged Valid RStatus {
                        offset: col[0],
                        replicate: False,
                        last: needCount - decNeedCount == 0,
                        burst_size: fromMaybe(?, currentReq[0]).burst_size,
                        id: fromMaybe(?, currentReq[0]).id
                    };
                    if (decNeedCount == 1 && nextCol != col + 1) begin
                        nextState = StartRead;
                    end
                end
            endcase
            if (needCount - decNeedCount == 0) begin
                nextState = Stop;
            end
            needCount <= needCount - decNeedCount;
            currentAddr[0] <= nextCurrentAddr;
        end else begin
            nextState = Idle;
        end
        state[0] <= nextState;
    endrule

    Reg#(Maybe#(AXI4_Write_Rq_Data#(AxiAddrWidth, AxiUserWidth))) writeReqBuffer <- mkReg(Invalid);

    rule startWrite if (state[0] == StartWrite);
        let needCountTmp = needCount;
        if (!outerPhy.wValid && !isValid(writeReqBuffer)) begin
            state[0] <= Idle;
        end else begin
            /*
            Col is always 2-byte aligned.
            ---------------------
            | [31:16] | [15: 0] |
            ---------------------
            |  Col 1  |  Col 0  |
            ---------------------
            For convince, we use 4-byte aligned address, `col` is always pointed to col 0.
            */
            let col = alignAddr(fromMaybe(?, currentAddr[0]), B4)[9:1];
            let nextAddrTmp = currentAddr[0];
            case(fromMaybe(?, currentReq[0]).burst_size) matches
                B1: begin
                    let req <- outerPhy.readWReq;
                    /*
                    No need to write all cols, because there's only 1-byte valid data.
                    But we still need to check which data block is valid.
                    */
                    let nextCol = ((req.strb[0] | req.strb[1]) == 1) ? False : True;
                    sdramPhy.write(tagged Cmd_Write {col: col + (nextCol ? 1 : 0), dqm: {req.strb[nextCol ? 3 : 1], req.strb[nextCol ? 2 : 0]}, data: nextCol ? req.data[31:16]: req.data[15:0]});
                    needCountTmp = needCountTmp - 1;
                    nextAddrTmp = tagged Valid nextAddr(fromMaybe(?, currentAddr[0]), fromMaybe(?, currentReq[0]));
                end
                B2: begin
                    if (!isValid(writeReqBuffer)) begin
                        let req <- outerPhy.readWReq;
                        if ((req.strb[0] | req.strb[1]) == 1) begin
                            if ((req.strb[2] | req.strb[3]) == 1) begin
                                /*
                                When using unaligned request, we need to check which data block is valid.
                                Maybe both cols have valid data, we need to buffer the request.
                                | [31:25] | [24:16] | [15: 8] |  [7:0]  |
                                |    X    |    O    |    O    |    X    |
                                |       Col 1       |       Col 0       |
                                */
                                writeReqBuffer <= tagged Valid req;
                            end
                            needCountTmp = needCountTmp - 1;
                            nextAddrTmp = tagged Valid nextAddr(fromMaybe(?, currentAddr[0]), fromMaybe(?, currentReq[0]));
                            sdramPhy.write(tagged Cmd_Write {col: col, dqm: {req.strb[1], req.strb[0]}, data: req.data[15:0]});
                        end else begin
                            sdramPhy.write(tagged Cmd_Write {col: col + 1, dqm: {req.strb[3], req.strb[2]}, data: req.data[31:16]});
                            needCountTmp = needCountTmp - 1;
                            nextAddrTmp = tagged Valid nextAddr(fromMaybe(?, currentAddr[0]), fromMaybe(?, currentReq[0]));
                        end
                    end else begin
                        sdramPhy.write(tagged Cmd_Write {col: col + 1, dqm: {fromMaybe(?, writeReqBuffer).strb[3], fromMaybe(?, writeReqBuffer).strb[2]}, data: fromMaybe(?, writeReqBuffer).data[31:16]});
                        writeReqBuffer <= tagged Invalid;
                    end
                end
                B4: begin
                    if (!isValid(writeReqBuffer)) begin
                        let req <- outerPhy.readWReq;
                        writeReqBuffer <= tagged Valid req;
                        sdramPhy.write(tagged Cmd_Write {col: col, dqm: {req.strb[1], req.strb[0]}, data: req.data[15:0]});
                    end else begin
                        nextAddrTmp = tagged Valid nextAddr(fromMaybe(?, currentAddr[0]), fromMaybe(?, currentReq[0]));
                        needCountTmp = needCountTmp - 1;
                        sdramPhy.write(tagged Cmd_Write {col: col + 1, dqm: {fromMaybe(?, writeReqBuffer).strb[3], fromMaybe(?, writeReqBuffer).strb[2]}, data: fromMaybe(?, writeReqBuffer).data[31:16]});
                        writeReqBuffer <= tagged Invalid;
                    end
                end
            endcase
            if (needCountTmp == 0) begin
                let id = fromMaybe(?, currentReq[0]).id;
                outerPhy.writeBResp(AXI4_Write_Rs {id: id, resp: OKAY, user: 0});
                currentAddr[0] <= tagged Invalid;
                currentReq[0] <= tagged Invalid;
                state[0] <= Idle;
            end else if (fromMaybe(?, nextAddrTmp)[24:12] != fromMaybe(?, currentAddr[0])[24:12])
            begin
                state[0] <= Idle;
            end else begin
                currentAddr[0] <= nextAddrTmp;
            end
            needCount <= needCountTmp;
        end
    endrule

    rule writeBeforePrecharge if (state[0] == StartWrite);
        beforePrechargeCount[1] <= 'd2;
    endrule

    rule beforePrechargeCountDec if (beforePrechargeCount[0] > 0 && state[0] != StartWrite);
        beforePrechargeCount[0] <= beforePrechargeCount[0] - 1;
    endrule

    rule beforeActCountDec if (beforeActCount[0] > 0);
        beforeActCount[0] <= beforeActCount[0] - 1;
    endrule

    rule stop if (state[0] == Stop);
        state[0] <= Idle;
        currentReq[0] <= tagged Invalid;
        currentAddr[0] <= tagged Invalid;
        sdramPhy.write(Cmd_Stop);
    endrule

    Vector#(3, Reg#(Maybe#(RStatus))) rStatusDelayVec <- replicateM(mkReg(defaultValue));
    rule casDelay;
        rStatusDelayVec[0] <= rStatus;
        rStatusDelayVec[1] <= rStatusDelayVec[0];
        rStatusDelayVec[2] <= rStatusDelayVec[1];
    endrule

    FIFOF#(RSplit) rfifo1 <- mkSizedFIFOF(4);
    rule readFromSdramPhy if (isValid(rStatusDelayVec[2]));
        let resp = RSplit {data: sdramPhy.read, rStatus: fromMaybe(?, rStatusDelayVec[2])};
        rfifo1.enq(resp);
    endrule

    Reg#(Maybe#(RSplit)) rSplitBuffer <- mkReg(Invalid);
    Reg#(Bit#(AxiDataWidth)) readDataBuffer <- mkRegU;

    rule readResp;
        let d = fromMaybe(?, rSplitBuffer);
        let data = readDataBuffer;
        if (!isValid(rSplitBuffer)) begin
            d = rfifo1.first;
            rfifo1.deq;
        end else begin
            rSplitBuffer <= Invalid;
        end
        data = d.rStatus.offset == 0 ? {data[31:16], d.data} : {d.data, data[15:0]};
        if ((d.rStatus.burst_size == B1)
            || (d.rStatus.burst_size == B2)
            || (d.rStatus.burst_size == B4 && d.rStatus.offset == 1))
        begin
            let resp = RResp {
                data: data,
                id: d.rStatus.id,
                resp: OKAY,
                last: d.rStatus.last
            };
            outerPhy.writeRResp(resp);
        end
        if (d.rStatus.replicate && !isValid(rSplitBuffer))
        begin
            rSplitBuffer <= tagged Valid d;
        end
        readDataBuffer <= data;
    endrule

    interface SdramIfc sdram = sdramPhy.out;
    interface AxiIfc axi = outerPhy.axi;
endmodule

endpackage
