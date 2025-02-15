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
    method Bool rRespNotFull;
    interface AxiIfc axi;
endinterface

typedef struct {
    Bit#(AxiIdWidth) id;
    Bit#(1) offset;
    Bool replicate;
    Bool last;
    AXI4_BurstSize burst_size;
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

typedef struct {
    Bit#(AxiAddrWidth) addr;
    Bit#(AxiIdWidth) id;
    AXI4_BurstType burst_type;
    AXI4_BurstSize burst_size;
    UInt#(8) burst_length;
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
    FIFOF#(AXI4_Read_Rs#(AxiDataWidth, AxiIdWidth, AxiUserWidth)) rRespFifo <- mkSizedFIFOF(8);

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

    method Bool rRespNotFull;
        return rRespFifo.notFull;
    endmethod

    interface AxiIfc axi;
        interface AXI4_Slave_Rd_Fab rd = s_rd.fab;
        interface AXI4_Slave_Wr_Fab wr = s_wr.fab;
    endinterface
endmodule

endpackage
