# vim:set syntax=tcl sw=2: #

set ::KIT_ROOT [file dir [info script]]

lappend auto_path [file join $KIT_ROOT lib]

package require socket
package require xdb-tcl

proc xdb-tcl::debug {args} {
  set datetime [clock format [clock seconds]]
  puts "debug: $datetime [::thread::id] % [join $args]"
}


namespace eval main {}

#======================================================================#
# main                                                                 #
#======================================================================#

proc main::listen {port} {
  socket::listen $port xdb-tcl::server::accept -thread {
    package require xdb-tcl
    package require Thread

    proc xdb-tcl::debug {args} {
      set datetime [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
      puts "debug: $datetime [::thread::id] % [join $args]"
    }
  }

  vwait forever
}

proc main::listen-tpool {port} {
  socket::listen $port xdb-tcl::server::accept -tpool {
    package require xdb-tcl
    package require Thread

    puts "init tpool"
    proc xdb-tcl::debug {args} {
      set datetime [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
      puts "debug: $datetime [::thread::id] % [join $args]"
    }
  }

  vwait forever
}

proc main::test {args} {
  package require tcltest
  ::tcltest::configure -verbose {pass}
  # ::tcltest::workingDirectory ./run-test
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

proc main::runtime-info {args} {
  puts "loaded = [info loaded]"
  puts "tsv::handlers = [tsv::handlers]" 
  package require Thread

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
