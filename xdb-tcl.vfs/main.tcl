# vim:set syntax=tcl sw=2: #

set ::KIT_ROOT [file dir [info script]]

lappend auto_path [file join $KIT_ROOT lib]


package require socket
package require xdb-tcl
package require retis

package require Thread
package require Ttrace

ttrace::eval {
  proc @debug {args} {
    set datetime [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
    puts "debug: $datetime [::thread::id] % [join $args]"
  }
}

#======================================================================#
# main task                                                            #
#======================================================================#

namespace eval main {}

source $KIT_ROOT/main/tclinfo.tcl
source $KIT_ROOT/main/test.tcl

proc main::listen {port args} {

  # set parallel "-thread"
  # set parallel "-tpool"

  set parallel [lindex $args 0]

  if {$parallel eq ""} {
    set parallel "-tpool"
  }

  socket::listen $port retis::server::accept $parallel {
    package require Ttrace

    package require xdb-tcl
  }

  vwait forever
}

proc main::help {} {
  puts "Usage:"
  puts ""
  puts "    [file tail $::argv0] listen \$port"
  puts ""
}

#======================================================================#
# main                                                                 #
#======================================================================#

set ::argv [lassign $::argv act]

if {[namespace which main::$act] ne ""} {
  main::$act {*}$::argv
} else {
  main::help
}

exit
