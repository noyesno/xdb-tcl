
proc ${NS}::session::read_comm {sock client} {
  variable sockbuf

  while {[gets $sock line]>=0} {
    append sockbuf $line

    if {[string is list -strict $sockbuf]} {
      lassign $sockbuf send id command
      # TODO: assert $send in "send async command"
      set sockbuf ""
      execute $client {*}$command
      return
    } else {
      append sockbuff "\n"
    }
  }

  # check eof
  if {[eof $sock]} {
    forget $client "eof read_comm"
    return
  }
}
