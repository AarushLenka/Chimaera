# Local physical repair screen for a completed Chimaera route.
# Invoke with CHIMAERA_REPAIR_RUN, CHIMAERA_REPAIR_LIB_DIR and
# CHIMAERA_REPAIR_OUTPUT_PREFIX set to absolute paths. The output must be
# rerouted, extracted and checked again; these repair-time reports are not
# signoff because newly inserted wiring has no extracted parasitics yet.
foreach name {CHIMAERA_REPAIR_RUN CHIMAERA_REPAIR_LIB_DIR CHIMAERA_REPAIR_OUTPUT_PREFIX} {
  if {![info exists ::env($name)]} {
    error "Missing environment variable $name"
  }
}
set root "$::env(CHIMAERA_REPAIR_RUN)/final"
set libs $::env(CHIMAERA_REPAIR_LIB_DIR)
set output $::env(CHIMAERA_REPAIR_OUTPUT_PREFIX)
foreach suffix {odb nl.v def sdc before.rpt provisional.rpt} {
  if {[file exists "$output.$suffix"]} {
    error "Refusing to overwrite $output.$suffix"
  }
}
set_thread_count 12
define_corners ss tt ff
foreach {corner suffix} {ss slow_1p08V_125C tt typ_1p20V_25C ff fast_1p32V_m40C} {
  read_liberty -corner $corner "$libs/sg13cmos5l_stdcell_${suffix}.lib"
}
read_db "$root/odb/tt_um_chimaera.odb"
read_sdc "$root/sdc/tt_um_chimaera.sdc"
foreach corner {ss tt ff} {
  read_spef -corner $corner "$root/spef/nom/tt_um_chimaera.nom.spef"
}
set_propagated_clock [all_clocks]
foreach corner {ss tt ff} {
  report_checks -corner $corner -path_delay min_max -fields {slew cap fanout} -digits 6 >> "$output.before.rpt"
  report_check_types -corner $corner -max_slew -max_capacitance -violators -digits 6 >> "$output.before.rpt"
}
set_wire_rc -signal -resistance 0.0003894512 -capacitance 0.0000969144
set_wire_rc -clock -resistance 0.0003894512 -capacitance 0.0000969144
remove_fillers
repair_design -slew_margin 20 -cap_margin 20 -max_utilization 85 -verbose
repair_timing -setup -setup_margin 0.25 -max_utilization 85 -verbose
repair_timing -hold -hold_margin 0.1 -setup_margin 0.25 -max_utilization 85 -verbose
detailed_placement
foreach corner {ss tt ff} {
  report_checks -corner $corner -path_delay min_max -fields {slew cap fanout} -digits 6 >> "$output.provisional.rpt"
}
# The old signal wiring must not become routing obstructions in the next GRT.
# Retain the special power-grid wires and route all ordinary nets afresh.
set count 0
foreach net [[ord::get_db_block] getNets] {
  set wire [$net getWire]
  if {$wire != "NULL" && ![$net isSpecial]} {
    odb::dbWire_destroy $wire
    incr count
  }
}
puts "CLEARED_REGULAR_ROUTES $count"
write_db "$output.odb"
write_verilog "$output.nl.v"
write_def "$output.def"
write_sdc "$output.sdc"
report_design_area
puts "Repair candidate saved. Fresh routing, extraction and all signoff checks are required."
