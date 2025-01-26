package ConstIfc;

typedef enum {
    PowerUp,
    Idle,
    Delay,
    PowerDown,
    WakeUp,
    Refresh,
    Precharge,
    Init,
    Act,
    Cmd,
    Wait
} StateEnum deriving (Bits, Eq, FShow);

typedef union tagged {
    void Nop;
    Bit#(9) ReadAddr;
    Bit#(9) WriteAddr;
    struct {
        Bit#(2) dqm;
        Bit#(16) data;
    } WriteData;
    void Stop;
    Maybe#(Bit#(2)) Precharge;
    Bool Refresh;
    void RefreshExit;
    struct {
        Bit#(13) row;
        Bit#(2) bank;
    } Activate;
    void PowerDown;
    void PowerDownExit;
    void ModeLoad;
} CmdEnum deriving (Bits, Eq, FShow);

endpackage
