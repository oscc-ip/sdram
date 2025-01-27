package OuterPhy;
import BlueAXI :: *;
import FIFOF :: *;
import GetPut::*;

typedef 32 AxiAddrWidth;
typedef 32 AxiDataWidth;
typedef 4 AxiIdWidth;
typedef 4 AxiUserWidth;

interface AxiIfc;
    interface AXI4_Slave_Rd_Fab#(AxiAddrWidth, AxiDataWidth, AxiIdWidth, AxiUserWidth) rd;
    interface AXI4_Slave_Wr_Fab#(AxiAddrWidth, AxiDataWidth, AxiIdWidth, AxiUserWidth) wr;
endinterface

interface OuterIfc;
    method Action write(Bit#(32) req);
    method Bit#(32) read;
    method Bool arValid;
    method Bool awValid;
    interface AxiIfc axi;
endinterface

(* synthesize *)
module mkOuterPhy(OuterIfc);
    AXI4_Slave_Rd#(AxiAddrWidth, AxiDataWidth, AxiIdWidth, AxiUserWidth) s_rd <- mkAXI4_Slave_Rd_Dummy;
    AXI4_Slave_Wr#(AxiAddrWidth, AxiDataWidth, AxiIdWidth, AxiUserWidth) s_wr <- mkAXI4_Slave_Wr_Dummy;

    FIFOF#(AXI4_Read_Rq#(AxiAddrWidth, AxiIdWidth, AxiUserWidth)) arReqFifo <- mkFIFOF;
    FIFOF#(AXI4_Write_Rq_Addr#(AxiAddrWidth, AxiIdWidth, AxiUserWidth)) awReqFifo <- mkFIFOF;

    rule arReqFifoRule;
        let d <- s_rd.request.get;
        arReqFifo.enq(d);
    endrule

    method Action write(Bit#(32) req);
    endmethod

    method Bit#(32) read;
        return 0;
    endmethod

    method Bool arValid;
        return arReqFifo.notEmpty;
    endmethod

    method Bool awValid;
        return awReqFifo.notEmpty;
    endmethod

    interface AxiIfc axi;
        interface AXI4_Slave_Rd_Fab rd = s_rd.fab;
        interface AXI4_Slave_Wr_Fab wr = s_wr.fab;
    endinterface
endmodule

endpackage
