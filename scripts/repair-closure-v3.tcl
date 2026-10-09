# Targeted ECO for the saved extracted-closure-v3-all layout, not a generic
# synthesis recipe. Refuse mismatched masters or load nets. Fresh routing and
# extraction are mandatory after this script; provisional STA is not signoff.
foreach name {CHIMAERA_REPAIR_RUN CHIMAERA_REPAIR_LIB_DIR CHIMAERA_REPAIR_OUTPUT_PREFIX} {
  if {![info exists ::env($name)]} {error "Missing environment variable $name"}
}
set root $::env(CHIMAERA_REPAIR_RUN)
set libs $::env(CHIMAERA_REPAIR_LIB_DIR)
set output $::env(CHIMAERA_REPAIR_OUTPUT_PREFIX)
foreach suffix {odb nl.v def sdc before.rpt provisional.rpt} {
  if {[file exists "$output.$suffix"]} {error "Refusing to overwrite $output.$suffix"}
}
set_thread_count 12
define_corners ss tt ff
foreach {corner suffix} {ss slow_1p08V_125C tt typ_1p20V_25C ff fast_1p32V_m40C} {
  read_liberty -corner $corner "$libs/sg13cmos5l_stdcell_${suffix}.lib"
}
read_db "$root/15-odb-cellfrequencytables/tt_um_chimaera.odb"
read_sdc "$root/14-openroad-fillinsertion/tt_um_chimaera.sdc"
foreach corner {ss tt ff} {
  read_spef -corner $corner "$root/16-openroad-rcx/nom/tt_um_chimaera.nom.spef"
}
set_propagated_clock [all_clocks]
set block [ord::get_db_block]

proc require_master {name expected} {
  set inst [[ord::get_db_block] findInst $name]
  if {$inst == "NULL"} {error "Missing ECO target $name"}
  set actual [[$inst getMaster] getName]
  if {$actual ne $expected || [$inst isDoNotTouch]} {
    error "ECO target $name has master $actual or is protected; expected $expected"
  }
}

proc resize_checked {name old new} {
  require_master $name $old
  replace_cell $name $new
  require_master $name $new
  puts "ECO_RESIZE $name $old -> $new"
}

proc buffer_checked {driver master port loads location name} {
  require_master $driver $master
  set inst [[ord::get_db_block] findInst $driver]
  set pin [$inst findITerm $port]
  if {$pin == "NULL"} {error "Missing driver pin $driver/$port"}
  set net [$pin getNet]
  foreach path $loads {
    set slash [string last / $path]
    set load_inst [[ord::get_db_block] findInst [string range $path 0 [expr {$slash - 1}]]]
    if {$load_inst == "NULL"} {error "Missing ECO load $path"}
    set load [$load_inst findITerm [string range $path [expr {$slash + 1}] end]]
    if {$load == "NULL" || [$load getNet] != $net || [$load getIoType] != "INPUT"} {
      error "ECO load $path is not an input on $driver/$port's net"
    }
  }
  insert_buffer -buffer_cell sg13cmos5l_buf_4 -load_pins [get_pins $loads] \
    -location $location -buffer_name $name -net_name ${name}_net
  # This OpenROAD version treats buffer/net names as prefixes and appends IDs.
  set new_net [$load getNet]
  if {$new_net == $net} {error "Buffer insertion did not move loads from $driver/$port"}
  set inserted ""
  foreach pin [$new_net getITerms] {
    if {[$pin getIoType] == "OUTPUT"} {set inserted [[$pin getInst] getName]}
  }
  if {$inserted == ""} {error "No buffer driver found on the new net"}
  require_master $inserted sg13cmos5l_buf_4
  foreach path $loads {
    set slash [string last / $path]
    set load_inst [[ord::get_db_block] findInst [string range $path 0 [expr {$slash - 1}]]]
    set pin [$load_inst findITerm [string range $path [expr {$slash + 1}] end]]
    if {[$pin getNet] != $new_net} {error "ECO load $path was not moved to the buffer output"}
  }
  puts "ECO_BUFFER $inserted DRIVER $driver/$port LOCATION $location LOADS $loads"
}

foreach corner {ss tt ff} {
  report_checks -corner $corner -path_delay min_max -fields {slew cap fanout} -digits 6 >> "$output.before.rpt"
  report_check_types -corner $corner -max_slew -max_capacitance -violators -digits 6 >> "$output.before.rpt"
}
remove_fillers

# The SS critical read gate has 0.198567 pF and 1.847082 ns cell delay.
resize_checked _46743_ sg13cmos5l_nand2b_1 sg13cmos5l_nand2b_2

# NAND3, NAND4 and A221OI have no stronger equivalent in the matched library.
# Isolate their long output wires with a nearby strong buffer instead.
buffer_checked _28470_ sg13cmos5l_nand3_1 Y \
  {_28524_/C rebuffer16681/A} {970 333} closure_v4_slew2
buffer_checked _44329_ sg13cmos5l_nand3_1 Y \
  {_44347_/B _44344_/B _44341_/B _44338_/B _44335_/B _44333_/A2 _44330_/A2} \
  {742 506} closure_v4_slew3
buffer_checked _29761_ sg13cmos5l_nand4_1 Y {_29762_/B1} {430 612} closure_v4_slew0
buffer_checked _44312_ sg13cmos5l_a221oi_1 Y {_44314_/B} {1135 506} closure_v4_slew1

# Partition long branches geographically; retain diode connections with their
# existing receiver groups. All capacitance limits and SDC remain unchanged.
buffer_checked fanout16749 sg13cmos5l_buf_1 X \
  {fanout3566/A fanout3559/A fanout3557/A fanout3545/A ANTENNA_215/A ANTENNA_216/A ANTENNA_217/A} \
  {550 450} closure_v4_cap0
buffer_checked fanout16756 sg13cmos5l_buf_1 X \
  {_31939_/A _31784_/B _31682_/A _31631_/A _31445_/A1 _31411_/A1 ANTENNA_224/A} \
  {1080 360} closure_v4_cap1
buffer_checked fanout4177 sg13cmos5l_buf_1 X \
  {_31936_/A _31781_/B _31731_/A _31679_/A ANTENNA_320/A ANTENNA_319/A ANTENNA_318/A ANTENNA_317/A} \
  {940 180} closure_v4_cap2
buffer_checked _27769_ sg13cmos5l_inv_1 Y \
  {_42691_/A1 _42489_/A1} {1080 600} closure_v4_cap3

detailed_placement
foreach corner {ss tt ff} {
  report_checks -corner $corner -path_delay min_max -fields {slew cap fanout} -digits 6 >> "$output.provisional.rpt"
  report_check_types -corner $corner -max_slew -max_capacitance -violators -digits 6 >> "$output.provisional.rpt"
}
# Retain special power wiring; ordinary wiring must be routed and extracted
# again after changing masters and connectivity.
set count 0
foreach net [$block getNets] {
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
puts "Targeted ECO saved. Reroute and re-extract before checking timing/electrical closure."
