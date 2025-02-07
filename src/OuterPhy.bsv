package OuterPhy;
import BlueAXI :: *;
import FIFOF :: *;
import GetPut::*;

typedef 32 AxiAddrWidth;
typedef 32 AxiDataWidth;
typedef 4 AxiIdWidth;
typedef 0 AxiUserWidth;

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
    method Bool wValid;
    interface AxiIfc axi;
endinterface

typedef struct {
    Bit#(AxiIdWidth) id;
    Bool last;
} RStatus deriving (Bits, Eq, FShow);

typedef struct {
    Bit#(16) data;
    RStatus rStatus;
} RSplit deriving (Bits, Eq, FShow);

typedef AXI4_Read_Rs#(AxiDataWidth, AxiIdWidth, AxiUserWidth) RResp;

instance DefaultValue#(RStatus);
    defaultValue = RStatus {
        id: 0,
        last: False
    };
endinstance

instance DefaultValue#(RSplit);
    defaultValue = RSplit {
        data: ?,
        rStatus: defaultValue
    };
endinstance

typedef union tagged {
    AXI4_Read_Rq#(AxiAddrWidth, AxiIdWidth, AxiUserWidth) READ_ADDR_REQ;
    AXI4_Write_Rq_Addr#(AxiAddrWidth, AxiIdWidth, AxiUserWidth) WRITE_ADDR_REQ;
} AddrReqType deriving (Bits, Eq, FShow);


(* synthesize *)
module mkOuterPhy(OuterIfc);
    /*
    We implemented Pipeline FIFOs in the AR and AW channels ourselves,
    so there's no need to buffer the input.
    */
    AXI4_Slave_Rd#(AxiAddrWidth, AxiDataWidth, AxiIdWidth, AxiUserWidth) s_rd <- mkAXI4_Slave_Rd(0, 1);
    AXI4_Slave_Wr#(AxiAddrWidth, AxiDataWidth, AxiIdWidth, AxiUserWidth) s_wr <- mkAXI4_Slave_Wr(0, 1, 1);

    FIFOF#(AXI4_Read_Rq#(AxiAddrWidth, AxiIdWidth, AxiUserWidth)) arReqFifo <- mkFIFOF;
    FIFOF#(AXI4_Write_Rq_Addr#(AxiAddrWidth, AxiIdWidth, AxiUserWidth)) awReqFifo <- mkFIFOF;
    FIFOF#(AXI4_Write_Rq_Data#(AxiDataWidth, AxiUserWidth)) wReqFifo <- mkFIFOF;

    rule arReqFifoEnq;
        let d <- s_rd.request.get;
        arReqFifo.enq(d);
    endrule

    rule awReqFifoEnq;
        let d <- s_wr.request_addr.get;
        awReqFifo.enq(d);
    endrule

    rule wReqFifoEnq;
        let d <- s_wr.request_data.get;
        wReqFifo.enq(d);
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
        wReqFifo.deq;
        return wReqFifo.first;
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

    method Bool wValid;
        return wReqFifo.notEmpty;
    endmethod

    interface AxiIfc axi;
        interface AXI4_Slave_Rd_Fab rd = s_rd.fab;
        interface AXI4_Slave_Wr_Fab wr = s_wr.fab;
    endinterface
endmodule

endpackage
