package SdramPhy;
import TriState :: *;
import ConstIfc :: *;

typedef CmdEnum SdramPhyRequest;
typedef Bit#(16) SdramPhyResponse;

(* always_ready, always_enabled *)
interface SdramIfc;
    method Bit#(1) csn;
    method Bit#(1) rasn;
    method Bit#(1) casn;
    method Bit#(1) wen;
    method Bit#(1) cke;
    method Bit#(2) dqm;
    method Bit#(13) addr;
    (* prefix = "" *) method Action dqiAction(Bit#(16) dqi);
    method Bit#(16) dqo;
    method Bit#(1) dqDir;
    method Bit#(2) bs;
endinterface

interface SdramPhyIfc;
    (* prefix = "" *)
    interface SdramIfc out;
    method Action write(SdramPhyRequest req);
    method SdramPhyResponse read;
endinterface

(* synthesize *)
module mkSdramPhy(SdramPhyIfc);
    Wire#(Bit#(16)) dqiIn <- mkWire;
    Wire#(Bit#(4)) cmdOut <- mkDWire('b0111);
    Wire#(Bit#(13)) addrOut <- mkDWire(0);
    Wire#(Bit#(16)) dqoOut <- mkDWire(0);
    Wire#(Bit#(1)) dqDirOut <- mkDWire(0);
    Wire#(Bit#(2)) dqmOut <- mkDWire(0);
    Wire#(Bit#(2)) bankOut <- mkDWire(0);
    Reg#(Bit#(1)) ckeReg[2] <- mkCReg(2, 0);

    method Action write(SdramPhyRequest req);
        case (req) matches
            tagged Cmd_Nop: cmdOut <= 'b0111;
            tagged Cmd_Read {.col}: begin
                cmdOut <= 'b0101;
                addrOut <= extend(col);
            end
            tagged Cmd_Write .d: begin
                cmdOut <= 'b0100;
                addrOut <= extend(d.col);
                dqmOut <= d.dqm;
                dqoOut <= d.data;
                dqDirOut <= 1;
            end
            tagged Cmd_Stop: begin
                cmdOut <= 'b0110;
            end
            tagged Cmd_Precharge .d: begin
                case (d) matches
                    tagged Valid {.bank}: begin
                        cmdOut <= 'b0010;
                        bankOut <= bank;
                    end
                    tagged Invalid: begin
                        cmdOut <= 'b0010;
                        Bit#(13) addrTmp = 0;
                        addrTmp[10] = 1;
                        addrOut <= addrTmp;
                    end
                endcase
            end
            tagged Cmd_Refresh .d: begin
                if (d) begin
                    ckeReg[0] <= 0;
                end
                cmdOut <= 'b0001;
            end
            tagged Cmd_RefreshExit: begin
                ckeReg[0] <= 1;
                cmdOut <= 'b0110;
            end
            tagged Cmd_Activate .d: begin
                cmdOut <= 'b0011;
                addrOut <= d.row;
                bankOut <= d.bank;
            end
            tagged Cmd_PowerDown: begin
                cmdOut <= 'b1000;
                ckeReg[0] <= 0;
            end
            tagged Cmd_PowerDownExit: begin
                cmdOut <= 'b1000;
                ckeReg[0] <= 1;
            end
            tagged Cmd_ModeLoad: begin
                cmdOut <= 'b0000;
                /*
                Burst Length: Full Page
                CAS Latency: 3
                Addressing Mode: Sequential
                Burst read and Single write
                */
                addrOut <= 'b0001000110111;
                bankOut <= 'b00;
            end
        endcase
    endmethod

    method SdramPhyResponse read();
        return dqiIn;
    endmethod

    interface SdramIfc out;
        method Action dqiAction(Bit#(16) dqi);
            dqiIn <= dqi;
        endmethod

        method Bit#(13) addr;
            return addrOut;
        endmethod

        method Bit#(1) csn;
            return cmdOut[3];
        endmethod

        method Bit#(1) rasn;
            return cmdOut[2];
        endmethod

        method Bit#(1) casn;
            return cmdOut[1];
        endmethod

        method Bit#(1) wen;
            return cmdOut[0];
        endmethod

        method Bit#(1) cke;
            return ckeReg[1];
        endmethod

        method Bit#(2) dqm;
            return dqmOut;
        endmethod

        method Bit#(16) dqo;
            return dqoOut;
        endmethod

        method Bit#(1) dqDir;
            return dqDirOut;
        endmethod

        method Bit#(2) bs;
            return bankOut;
        endmethod
    endinterface
endmodule
endpackage
