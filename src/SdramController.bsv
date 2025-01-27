package SdramController;
import SdramPhy :: *;
import OuterPhy :: *;
import ConstIfc :: *;
import StmtFSM :: *;

interface SdramControllerIfc;
    interface AxiIfc axi;
    interface SdramIfc sdram;
endinterface

(* synthesize *)
module mkSdramController(SdramControllerIfc);
    let sdramPhy <- mkSdramPhy;
    let outerPhy <- mkOuterPhy;

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

    interface SdramIfc sdram = sdramPhy.out;
    interface AxiIfc axi = outerPhy.axi;
endmodule

endpackage
