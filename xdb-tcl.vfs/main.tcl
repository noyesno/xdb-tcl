set KIT_ROOT [file dir [info script]]
lappend auto_path [file join $KIT_ROOT lib]

package require xdb-tcl

proc xdb-tcl::debug {args} {
  set datetime [clock format [clock seconds]]
  puts "debug: $datetime % [join $args]"
}

lassign $::argv port

xdb-tcl::listen $port

vwait forever
