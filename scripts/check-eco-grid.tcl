# Read-only footprint and power-grid probe for a resumed final ECO database.
# Use OpenROAD -metrics OUTPUT.json. This never rewrites the checked ODB.
foreach name {CHIMAERA_CHECK_ODB CHIMAERA_CHECK_LIB CHIMAERA_CHECK_REPORT_PREFIX} {
  if {![info exists ::env($name)]} {error "Missing environment variable $name"}
}
set input $::env(CHIMAERA_CHECK_ODB)
set prefix $::env(CHIMAERA_CHECK_REPORT_PREFIX)
foreach net {VPWR VGND} {
  if {[file exists "$prefix-$net-grid-errors.rpt"]} {
    error "Refusing to overwrite $prefix-$net-grid-errors.rpt"
  }
}
set before [exec python3 -c {import hashlib,sys; print(hashlib.file_digest(open(sys.argv[1], "rb"), "sha256").hexdigest())} $input]
read_liberty $::env(CHIMAERA_CHECK_LIB)
read_db $input
set block [ord::get_db_block]
set die [$block getDieArea]
set units [$block getDbUnitsPerMicron]
set bbox {}
foreach coordinate [list [$die xMin] [$die yMin] [$die xMax] [$die yMax]] {
  lappend bbox [expr {double($coordinate) / $units}]
}
utl::metric design__die__bbox [join $bbox " "]
foreach net {VPWR VGND} {
  set power [$block findNet $net]
  if {$power == "NULL" || [llength [$power getSWires]] == 0 || [llength [$power getBTerms]] == 0} {
    error "Power net $net lacks grid wiring or external terminals"
  }
  check_power_grid -net $net -error_file "$prefix-$net-grid-errors.rpt"
  set report "$prefix-$net-grid-errors.rpt"
  if {[file exists $report]} {
    set stream [open $report r]
    set errors [string trim [read $stream]]
    close $stream
    if {$errors ne ""} {error "Power-grid error report is nonempty: $report"}
  }
  puts "GRID_CHECK_COMPLETED $net"
}
set after [exec python3 -c {import hashlib,sys; print(hashlib.file_digest(open(sys.argv[1], "rb"), "sha256").hexdigest())} $input]
if {$before ne $after} {error "Input ODB changed during the power-grid probe"}
utl::metric_integer design__power_grid_violation__count 0
utl::metric chimaera__checked_odb__sha256 $after
puts "READ_ONLY_GRID_PROBE_COMPLETED $after"
