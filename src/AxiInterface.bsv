package AxiInterface;
import BlueAXI :: *;

module mkAxiInterface(Empty);
    AXI4_Slave_Rd#(32, 32, 4, 4) s_rd <- mkAXI4_Slave_Rd_Dummy;
    AXI4_Slave_Wr#(32, 32, 4, 4) s_wr <- mkAXI4_Slave_Wr_Dummy;
endmodule

endpackage
