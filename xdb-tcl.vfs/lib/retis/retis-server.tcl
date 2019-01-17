
#----------------------------------------------------------------------#
# Simple Listen                                                        #
#----------------------------------------------------------------------#

proc ${NS}::server::listen {port} {
  set ns [namespace current]

  set ssock [socket -server [list ${ns}::server::accept] $port]

  @debug "listen $port ..."
}

#----------------------------------------------------------------------#
# accept - the enry point for a client
#----------------------------------------------------------------------#

proc ${NS}::server::accept {sock client_addr client_port {cleanup ""}} {
  @debug "accept $client_addr:$client_port"

  chan configure $sock -blocking 0 -encoding utf-8 -translation lf

  set ns  [namespace current]
  set pns [namespace parent]

  set session [${pns}::session $sock new]


  set timeout [expr 1000*10]  ;# 10 seconds
  set watchdog [list $timeout [list $session close "watchdog"]]
  $session set watchdog $watchdog
  $session watchdog start

  chan event $sock readable [list ${pns}::session::read_command $sock $session]

  if {$cleanup ne ""} {
    $session wait

    uplevel 1 $cleanup
  }
}
