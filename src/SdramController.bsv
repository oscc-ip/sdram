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
    Reg#(Maybe#(Bit#(AxiAddrWidth))) currentAddr <- mkReg(Invalid);

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
        currentAddr <= Invalid;
    endrule

    rule prechargeAllDone if (hasPrecharged && state[0] == Precharge);
        prechargeFsm.waitTillDone;
        hasPrecharged <= False;
        state[0] <= backState;
        prechargeCount <= 0;
    endrule

    rule prechargeCountIncrease if (isValid(currentAddr));
        prechargeCount <= prechargeCount + 1;
    endrule

    rule refreshCountDecrease(state[0] != Refresh && state[0] != PowerUp);
        refreshCount <= refreshCount - 1;
    endrule

    Reg#(AddrReqType) currentAddrReq <- mkRegU;

    rule idle if (state[1] == Idle);
        AddrReqType addrReq = Invalid;
        if(isValid(currentAddr) && (prechargeCount >= 20_000 - 5 || refreshCount < 24)) begin
            backState <= Idle;
            state[1] <= Precharge;
        end else if (refreshCount < 24) begin
            backState <= Idle;
            state[1] <= Refresh;
        end else begin
            if (outerPhy.awValid && (isCurrentRead || (!isCurrentRead && !outerPhy.arValid))) begin
                let d <- outerPhy.readAwReq;
                addrReq = WRITE_ADDR_REQ(d);
                isCurrentRead <= False;
            end else if (outerPhy.arValid) begin
                let d <- outerPhy.readArReq;
                addrReq = READ_ADDR_REQ(d);
                isCurrentRead <= True;
            end
            let noNeedAct = (isValid(currentAddr) && case(addrReq) matches
                tagged READ_ADDR_REQ .d:
                    return d.addr[24:10] == fromMaybe(?, currentAddr)[24:10];
                tagged WRITE_ADDR_REQ .d:
                    return d.addr[24:10] == fromMaybe(?, currentAddr)[24:10];
                tagged Invalid:
                    return False;
            endcase);
            let isValidAddrReq = (case(addrReq) matches
                tagged READ_ADDR_REQ .*:
                    return True;
                tagged WRITE_ADDR_REQ .*:
                    return True;
                tagged Invalid:
                    return False;
            endcase);
            currentAddrReq <= addrReq;
            if (isValidAddrReq) begin
                if (noNeedAct) begin
                    state[1] <= Cmd;
                end else begin
                    state[1] <= Precharge;
                    backState <= Act;
                end
            end
        end
    endrule

    /*
    Row: [24:12], Bank: [11:10], Col: [9:1], [0]
    */
    rule act if (state[0] == Act);
        sdramPhy.write(tagged Cmd_Activate {row: pack(currentAddrReq)[24:12], bank: pack(currentAddrReq)[11:10]});
    endrule

    rule cmd if (state[0] == Cmd);
        case(currentAddrReq) matches
            tagged READ_ADDR_REQ .d:
                noAction;
            tagged WRITE_ADDR_REQ .d:
                noAction;
        endcase
        sdramPhy.write(Cmd_ReadAddr(0));
    endrule

    Maybe#(RStatus) rStatus = isCurrentRead && (state[0] == Cmd || state[0] == Wait) ? tagged Valid RStatus {id: 0, last: False} : Invalid;
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
