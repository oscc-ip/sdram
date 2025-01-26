package SdramController;
import SdramPhy :: *;
import AxiInterface :: *;

interface SdramControllerIfc;
    method Action write(SdramPhyRequest req);
    method SdramPhyResponse read;
    interface SdramIfc out;
endinterface

(* synthesize *)
module mkSdramController(SdramControllerIfc);
    let sdramPhy <- mkSdramPhy;
    let axi <- mkAxiInterface;

    interface SdramIfc out = sdramPhy.out;
endmodule

endpackage
