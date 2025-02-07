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
    Finish,
    Stop
} StateEnum deriving (Bits, Eq, FShow);

typedef union tagged {
    void Cmd_Nop;
    Bit#(9) Cmd_Read;
    struct {
        Maybe#(Bit#(9)) col;
        Bit#(2) dqm;
        Bit#(16) data;
    } Cmd_Write;
    void Cmd_Stop;
    Maybe#(Bit#(2)) Cmd_Precharge;
    // True for self-refresh, False for auto-refresh
    Bool Cmd_Refresh;
    void Cmd_RefreshExit;
    struct {
        Bit#(13) row;
        Bit#(2) bank;
    } Cmd_Activate;
    void Cmd_PowerDown;
    void Cmd_PowerDownExit;
    void Cmd_ModeLoad;
} CmdEnum deriving (Bits, Eq, FShow);

endpackage
