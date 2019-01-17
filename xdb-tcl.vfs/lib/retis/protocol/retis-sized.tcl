
proc ${NS}::session::read_sized {sock client args} {

  if {[llength $args]==0} {
    set size [gets $sock]
  } else {
    set size [lindex $args 0]
  }

  if {$size eq ""} {
    if {[eof $sock]} {
      $client close "eof read_sized"
      return
    }
    @debug "see empty size"
    return
  }

  @debug "size = $size"
  set command [read $sock $size]
  gets $sock
  @debug $size $command
  execute $client {*}$command
}
