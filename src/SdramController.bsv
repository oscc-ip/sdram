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

    Reg#(StateEnum) state[3] <- mkCReg(3, PowerUp);
    Reg#(StateEnum) backState <- mkRegU;

    Reg#(Bit#(32)) refreshCount <- mkRegU;
    Reg#(Bit#(32)) prechargeCount <- mkReg(0);
    Reg#(Maybe#(Bit#(AxiAddrWidth))) currentActiveAddr <- mkReg(Invalid);

    Reg#(Bit#(32)) i <- mkRegU;

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
        prechargeFsm.start;
        hasPrecharged <= True;
        currentActiveAddr <= Invalid;
    endrule

    rule prechargeAllDone if (hasPrecharged && state[0] == Precharge);
        prechargeFsm.waitTillDone;
        hasPrecharged <= False;
        state[0] <= backState;
        prechargeCount <= 0;
    endrule

    rule prechargeCountIncrease if (isValid(currentActiveAddr) && state[0] != Precharge);
        prechargeCount <= prechargeCount + 1;
    endrule

    rule refreshCountDecrease(state[0] != Refresh && state[0] != PowerUp);
        refreshCount <= refreshCount - 1;
    endrule

    Reg#(Maybe#(AddrReqType)) currentReq <- mkReg(Invalid);

    rule idle if (state[1] == Idle);
        let addrReq = currentReq;
        if(isValid(currentActiveAddr) && (prechargeCount >= 20_000 - 5 || refreshCount < 24)) begin
            backState <= Idle;
            state[1] <= Precharge;
        end else if (refreshCount < 24) begin
            backState <= Idle;
            state[1] <= Refresh;
        end else begin
            if(!isValid(currentReq)) begin
                if (outerPhy.awValid && (isCurrentRead || (!isCurrentRead && !outerPhy.arValid))) begin
                    let d <- outerPhy.readAwReq;
                    addrReq = tagged Valid WRITE_ADDR_REQ(d);
                    isCurrentRead <= False;
                end else if (outerPhy.arValid) begin
                    let d <- outerPhy.readArReq;
                    addrReq = tagged Valid READ_ADDR_REQ(d);
                    isCurrentRead <= True;
                end
            end
            if (isValid(addrReq)) begin
                currentReq <= addrReq;
                let noNeedAct = (isValid(currentActiveAddr) && case(fromMaybe(?, addrReq)) matches
                    tagged READ_ADDR_REQ .d:
                        return d.addr[24:10] == fromMaybe(?, currentActiveAddr)[24:10];
                    tagged WRITE_ADDR_REQ .d:
                        return d.addr[24:10] == fromMaybe(?, currentActiveAddr)[24:10];
                endcase);
                if (noNeedAct) begin
                    state[1] <= Act;
                end else begin
                    state[1] <= Precharge;
                    backState <= Act;
                end
            end
        end
    endrule

    Reg#(Bit#(32)) delayCount <- mkRegU;

    /*
    Row: [24:12], Bank: [11:10], Col: [9:1], [0]
    */
    rule act if (state[2] == Act);
        if (isValid(currentActiveAddr)) begin
            case (fromMaybe(?, currentReq)) matches
                tagged READ_ADDR_REQ .d:
                    state[2] <= Cmd;
                tagged WRITE_ADDR_REQ .d:
                    begin
                        // if WFifo.valid
                        state[2] <= Cmd;
                    end
            endcase
        end else begin
            let addr = case (fromMaybe(?, currentReq)) matches
                tagged READ_ADDR_REQ .d:
                    return d.addr;
                tagged WRITE_ADDR_REQ .d:
                    return d.addr;
            endcase;
            sdramPhy.write(tagged Cmd_Activate {row: addr[24:12], bank: addr[11:10]});
            currentActiveAddr <= tagged Valid addr;
            state[2] <= Delay;
            delayCount <= 3;
            backState <= Act;
        end
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

    Reg#(UInt#(16)) needCount <- mkRegU;

    rule cmd if (state[0] == Cmd);
        let col = fromMaybe(?, currentActiveAddr)[9:1];
        if (isCurrentRead) begin
            sdramPhy.write(Cmd_Read(col));
        end else begin
            sdramPhy.write(tagged Cmd_Write {col: tagged Valid col, dqm: 0, data: 0});
        end
        let burst_length = case (fromMaybe(?, currentReq)) matches
            tagged READ_ADDR_REQ .d:
                return d.burst_length;
            tagged WRITE_ADDR_REQ .d:
                return d.burst_length;
        endcase;
        let burst_size = case (fromMaybe(?, currentReq)) matches
            tagged READ_ADDR_REQ .d:
                return d.burst_size;
            tagged WRITE_ADDR_REQ .d:
                return d.burst_size;
        endcase;
        let addr = case (fromMaybe(?, currentReq)) matches
            tagged READ_ADDR_REQ .d:
                return d.addr;
            tagged WRITE_ADDR_REQ .d:
                return d.addr;
        endcase;

        let crossBoundary = addr[0] == 1;
        needCount <= (isCurrentRead ? (case (burst_size) matches
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
        endcase) : (extend(burst_length) << 1)) - 1;
        state[0] <= Finish;
    endrule

    rule finish if (state[1] == Finish);
        // todo: !wValid / rFull / crossBank
        if (needCount == 0) begin
            state[1] <= Stop;
        end else begin
            needCount <= needCount - 1;
        end
    endrule

    rule stop if (state[0] == Stop);
        state[0] <= Idle;
        currentReq <= tagged Invalid;
        sdramPhy.write(Cmd_Stop);
    endrule

    Maybe#(RStatus) rStatus = isCurrentRead && (state[0] == Cmd || state[0] == Finish) ? tagged Valid RStatus {id: 0, last: False} : Invalid;
    Vector#(3, Reg#(Maybe#(RStatus))) rStatusDelayVec <- replicateM(mkReg(defaultValue));
    rule casDelay;
        rStatusDelayVec[0] <= rStatus;
        rStatusDelayVec[1] <= rStatusDelayVec[0];
        rStatusDelayVec[2] <= rStatusDelayVec[1];
    endrule

    Gearbox#(1, 2, RSplit) rfifo1 <- mk1toNGearbox(defaultClock, defaultReset, defaultClock, defaultReset);
    FIFOF#(RSplit) rfifo2 <- mkSizedFIFOF(4);
    rule readFromSdramPhy if (isValid(rStatusDelayVec[2]));
        let resp = RSplit {data: sdramPhy.read, rStatus: fromMaybe(?, rStatusDelayVec[2])};
        rfifo2.enq(resp);
    endrule

    rule scaleUp;
        rfifo1.enq(unpack(pack(rfifo2.first)));
        rfifo2.deq;
    endrule

    rule readResp;
        rfifo1.deq;
        let d = rfifo1.first;
        let data = {d[0].data, d[1].data};
        let resp = RResp {
            data: data,
            id: d[1].rStatus.id,
            resp: d[0].rStatus.id == d[1].rStatus.id && !d[0].rStatus.last ? OKAY : SLVERR,
            last: d[1].rStatus.last,
            user: 0
        };
        outerPhy.writeRResp(resp);
    endrule

    rule writeResp;
        // outerPhy.writeRResp();
    endrule

    interface SdramIfc sdram = sdramPhy.out;
    interface AxiIfc axi = outerPhy.axi;
endmodule

endpackage
