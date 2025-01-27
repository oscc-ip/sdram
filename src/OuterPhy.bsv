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
    method ActionValue#(AXI4_Read_Rq#(AxiAddrWidth, AxiIdWidth, AxiUserWidth)) readArReq;
    method ActionValue#(AXI4_Write_Rq_Addr#(AxiAddrWidth, AxiIdWidth, AxiUserWidth)) readAwReq;
    method ActionValue#(AXI4_Write_Rq_Data#(AxiAddrWidth, AxiUserWidth)) readWReq;
    method Action writeRResp(AXI4_Read_Rs#(AxiDataWidth, AxiIdWidth, AxiUserWidth) resp);
    method Action writeBResp(AXI4_Write_Rs#(AxiIdWidth, AxiUserWidth) resp);
    method Bool arValid;
    method Bool awValid;
    interface AxiIfc axi;
endinterface

typedef union tagged {
    AXI4_Read_Rq#(AxiAddrWidth, AxiIdWidth, AxiUserWidth) READ_ADDR_REQ;
    AXI4_Write_Rq_Addr#(AxiAddrWidth, AxiIdWidth, AxiUserWidth) WRITE_ADDR_REQ;
    void Invalid;
} AddrReqType deriving (Bits, Eq, FShow);


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

    method ActionValue#(AXI4_Read_Rq#(AxiAddrWidth, AxiIdWidth, AxiUserWidth)) readArReq;
        arReqFifo.deq;
        return arReqFifo.first;
    endmethod

    method ActionValue#(AXI4_Write_Rq_Addr#(AxiAddrWidth, AxiIdWidth, AxiUserWidth)) readAwReq;
        awReqFifo.deq;
        return awReqFifo.first;
    endmethod

    method ActionValue#(AXI4_Write_Rq_Data#(AxiAddrWidth, AxiUserWidth)) readWReq;
        let d <- s_wr.request_data.get;
        return d;
    endmethod

    method Action writeRResp(AXI4_Read_Rs#(AxiDataWidth, AxiIdWidth, AxiUserWidth) resp);
        s_rd.response.put(resp);
    endmethod

    method Action writeBResp(AXI4_Write_Rs#(AxiIdWidth, AxiUserWidth) resp);
        s_wr.response.put(resp);
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
