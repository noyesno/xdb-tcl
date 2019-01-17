
proc ${NS}::session::read_telnet {sock client args} {
  if {[llength $args]==0} {
    set line [gets $sock]
  } else {
    set line [lindex $args 0]
  }

  set command $line

  if {$command ne ""} {
    execute $client {*}$command
  }

  # check eof
  if {[eof $sock]} {
    forget $client "eof read_telnet"
    return
  }

  return
}
