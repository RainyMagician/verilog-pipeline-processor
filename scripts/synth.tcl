set_app_var search_path "$search_path mapped lib scripts rtl cons"
set_app_var target_library saed90nm_typ.db
set_app_var link_library "* $target_library"


read_verilog "pipeline_riscv.v"
current_design pipeline_riscv
link
check_design > check_design.log
source timing.con
compile
report_constraint -all_violators > constraint_report.log
report_area > area_report.log
report_timing > timing_report.log
write_sdf -version 1.0 mapped/pipeline_riscv.sdf
write -f verilog -hier -out mapped/pipeline_riscv_mapped.v
quit
