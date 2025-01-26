package SdramPhy;
import TriState :: *;
import ConstIfc :: *;

typedef CmdEnum SdramPhyRequest;

typedef struct {
    Bit#(16) data;
} SdramPhyResponse deriving (Bits, Eq, FShow);

(* always_ready, always_enabled *)
interface SdramIfc;
    method Bit#(1) csn;
    method Bit#(1) rasn;
    method Bit#(1) casn;
    method Bit#(1) wen;
    method Bit#(1) cke;
    method Bit#(2) dqm;
    method Bit#(13) addr;
    method Action dqi(Bit#(16) data);
    method Bit#(16) dqo;
    method Bit#(1) dqDir;
endinterface

interface SdramPhyIfc;
    (* prefix = "" *)
    interface SdramIfc out;
    method Action write(SdramPhyRequest req);
    method Bit#(16) read;
endinterface

module mkSdramPhy(SdramPhyIfc);
    Wire#(Bit#(16)) dqiIn <- mkWire;
    Wire#(Bit#(4)) cmdOut <- mkDWire('b0111);
    Wire#(Bit#(13)) addrOut <- mkDWire(0);
    Wire#(Bit#(16)) dqoOut <- mkDWire(0);
    Wire#(Bit#(1)) dqDirOut <- mkDWire(0);
    Wire#(Bit#(2)) dqmOut <- mkDWire(0);
    Wire#(Bit#(2)) bankOut <- mkDWire(0);
    Reg#(Bit#(1)) ckeReg <- mkReg(0);
    RWire#(Bit#(1)) ckeWire <- mkRWire();

    rule ckeWriteBack;
        if (isValid(ckeWire.wget())) begin
            ckeReg <= fromMaybe(?, ckeWire.wget());
        end
    endrule

    method Action write(SdramPhyRequest req);
        case (req) matches
            tagged Nop: cmdOut <= 'b0111;
            tagged ReadAddr {.col}: begin
                cmdOut <= 'b0101;
                addrOut <= extend(col);
            end
            tagged WriteAddr {.col}: begin
                cmdOut <= 'b0100;
                addrOut <= extend(col);
                dqDirOut <= 1;
            end
            tagged WriteData .d: begin
                cmdOut <= 'b0000;
                dqmOut <= d.dqm;
                dqoOut <= d.data;
                dqDirOut <= 1;
            end
            tagged Stop: begin
                cmdOut <= 'b0110;
            end
            tagged Precharge .d: begin
                case (d) matches
                    tagged Valid {.bank}: begin
                        cmdOut <= 'b0010;
                        bankOut <= bank;
                        addrOut <= 'b0010000000000;
                    end
                    tagged Invalid: begin
                        cmdOut <= 'b0010;
                    end
                endcase
            end
            tagged Refresh .d: begin
                if (d) begin
                    ckeWire.wset(0);
                end
                cmdOut <= 'b0001;
            end
            tagged RefreshExit: begin
                ckeWire.wset(1);
                cmdOut <= 'b0110;
            end
            tagged PowerDown: begin
                cmdOut <= 'b1000;
                ckeWire.wset(0);
            end
            tagged PowerDownExit: begin
                cmdOut <= 'b1000;
                ckeWire.wset(1);
            end
            tagged ModeLoad: begin
                cmdOut <= 'b0000;
                /*
                * Burst Length: Full Page
                * CAS Latency: 3
                * Addressing Mode: Sequential
                * Burst read and Burst write
                */
                addrOut <= 'b0000000110111;
            end
        endcase
    endmethod

    method Bit#(16) read();
        return dqiIn;
    endmethod

    interface SdramIfc out;
        method Action dqi(Bit#(16) data);
            dqiIn <= data;
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
            return fromMaybe(ckeReg, ckeWire.wget());
        endmethod
    endinterface

endmodule

endpackage
