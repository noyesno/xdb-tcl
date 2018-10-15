set KIT_ROOT [file dir [info script]]
lappend auto_path [file join $KIT_ROOT lib]

package require xdb-tcl

proc xdb-tcl::debug {args} {
  set datetime [clock format [clock seconds]]
  puts "debug: $datetime % [join $args]"
}


namespace eval main {}

proc main::listen {args} {
  lassign $args port
  xdb-tcl::listen $port
  vwait forever
}

proc main::test {args} {
  package require tcltest
  ::tcltest::configure -verbose {pass}
  # uplevel #0 { namespace import ::tcltest::* }

  lassign $args tclfile

  if [file isfile $tclfile] {
    uplevel #0 source $tclfile
  } elseif [file isdir $tclfile] {
    ::tcltest::configure -testdir $tclfile
    ::tcltest::runAllTests
  }
  exit
}

proc main::help {} {
  puts "Usage:"
  puts ""
  puts "    [file tail $::argv0] listen \$port"
  puts ""
}

set ::argv [lassign $::argv act]

if {[namespace which main::$act] ne ""} {
  main::$act {*}$::argv
} else {
  main::help
}

exit
