
#----------------------------------------------------------------------#
# service command
#----------------------------------------------------------------------#

proc retis::service::ping {client args} {
    return [$client reply "pone $args"]
}

proc retis::service::apply {client args} {
  set apply_argv [lassign $args apply_args apply_body]
  set result [::apply [list $apply_args $apply_body] {*}$apply_argv]
  return [reply_result $client $result]
}
