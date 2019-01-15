# vim:set syntax=tcl: #

namespace eval ::argv {

}

proc ::argv::parse {argv argwant {argkeys ""}} {
    set kargs [dict create]
    set argv_left [list]

    for { set argidx 0 ; set argc [llength $argv] } {$argidx<$argc} {incr argidx} {
      set arg [lindex $argv $argidx]
      if {$arg in $argwant} {
        dict set kargs $arg [lindex $argv [incr argidx]]
      } else {
        lappend argv_left $arg
      }
    }

    puts "argv_left = $argv_left argkeys = $argkeys"
    foreach key $argkeys value $argv_left {
      if {$key ne "" && $key in $argwant} {
        dict set kargs $key $value
      }
    }

    foreach key $argwant {
      dict append kargs $key  ;# create if missing
    }

    return $kargs
}



puts [argv::parse [list a b c] "-sql -bind -var -filter" {-sql -var -filter}]
