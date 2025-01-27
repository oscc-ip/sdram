package SdramController;
import SdramPhy :: *;
import OuterPhy :: *;
import ConstIfc :: *;
import StmtFSM :: *;
import FIFOF :: *;
import Vector :: *;
import Gearbox :: *;

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

    Reg#(StateEnum) state <- mkReg(PowerUp);

    let powerUpFsm <- mkFSM( seq
        // $display("Nop 20_000 cycles...");
        delay(20_000);
        // $display("Precharge all banks...");
        sdramPhy.write(Cmd_Precharge(Invalid));
        delay(3);
        // $display("Refresh...");
        sdramPhy.write(Cmd_Refresh(False));
        delay(11);
        // $display("Refresh...");
        sdramPhy.write(Cmd_Refresh(False));
        delay(11);
        // $display("Load mode...");
        sdramPhy.write(Cmd_ModeLoad);
    endseq );

    Reg#(Bool) isCurrentRead <- mkReg(False);
    Reg#(Bool) hasInitiated <- mkReg(False);

    rule powerUp if (!hasInitiated && state == PowerUp);
        powerUpFsm.start;
        hasInitiated <= True;
    endrule

    rule powerUpDone if (hasInitiated && state == PowerUp);
        powerUpFsm.waitTillDone;
        state <= Idle;
    endrule

    rule idle if (state == Idle);
        if (outerPhy.arValid || outerPhy.awValid) begin
            state <= Init;
        end
    endrule

    Reg#(AddrReqType) currentAddrReq <- mkReg(WRITE_ADDR_REQ(?));

    rule init if (state == Init);
        AddrReqType addrReq = Invalid;
        if (outerPhy.awValid && ((isCurrentRead) || (!isCurrentRead && !outerPhy.arValid))) begin
            let d <- outerPhy.readAwReq;
            addrReq = WRITE_ADDR_REQ(d);
            state <= Cmd;
        end else if (outerPhy.arValid) begin
            let d <- outerPhy.readArReq;
            addrReq = READ_ADDR_REQ(d);
            state <= Cmd;
        end
        if (addrReq != Invalid) begin
            currentAddrReq <= addrReq;
            if ((outerPhy.awValid && isCurrentRead) || (outerPhy.arValid && !isCurrentRead)) begin
                isCurrentRead <= !isCurrentRead;
            end
        end
    endrule

    let isRead = isCurrentRead && (state == Cmd || state == Wait);
    Vector#(3, Reg#(Bool)) isReadDelayVec <- replicateM(mkReg(False));
    rule isReadDelay;
        isReadDelayVec[0] <= isRead;
        isReadDelayVec[1] <= isReadDelayVec[0];
        isReadDelayVec[2] <= isReadDelayVec[1];
    endrule

    Gearbox#(1, 4, SdramPhyResponse) rfifo1 <- mk1toNGearbox(defaultClock, defaultReset, defaultClock, defaultReset);
    FIFOF#(SdramPhyResponse) rfifo2 <- mkSizedFIFOF(4);
    rule readFromSdramPhy if (isReadDelayVec[2]);
        let resp = sdramPhy.read;
        rfifo2.enq(resp);
    endrule

    rule scaleUp;
        rfifo1.enq(unpack(rfifo2.first));
        rfifo2.deq;
    endrule

    interface SdramIfc sdram = sdramPhy.out;
    interface AxiIfc axi = outerPhy.axi;
endmodule

endpackage
