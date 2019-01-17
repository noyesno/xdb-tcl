
proc ${NS}::session::read_redis {sock client args} {

  if {[llength $args]==0} {
    set line [gets $sock]
  } else {
    set line [lindex $args 0]
  }

  if {[string index $line 0] eq "$"} {
    set size [string range $line 1 end-1]
    set command [read $sock $size]
    read $sock 2 ;# discard "\r\n"
    # set command [encoding convertfrom utf-8 $command]
  } elseif {[string index $line 0] eq "*"} {
    set n [string range $line 1 end-1]
    set command [list]
    while {$n} {
      incr n -1
      gets $sock line
      set size [string range $line 1 end-1]
      set arg [read $sock $size]
      read $sock 2 ;# discard "\r\n"
      # set arg [encoding convertfrom utf-8 $arg]
      lappend command $arg
    }
  } elseif {$line ne ""} {
    # TODO
    set size $line
    set command [read $sock $size]
    gets $sock
  }

  # check eof
  if {[eof $sock]} {
    $client close "eof redis"
    return
  }

  @debug "request redis = $command"
  execute $client {*}$command
}
