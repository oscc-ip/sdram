set PROJ_PATH "[file dirname [info script]]/.."
set SDC_FILE   [lindex $argv 0]
set NETLIST_V  [lindex $argv 1]
set DESIGN     [lindex $argv 2]
set RESULT_DIR [lindex $argv 3]
set LIB_FILES  $PROJ_PATH/lib/nangate/lib/merged.lib

set_design_workspace $RESULT_DIR
read_netlist $NETLIST_V
read_liberty $LIB_FILES
link_design $DESIGN
read_sdc  $SDC_FILE
report_timing
report_power
