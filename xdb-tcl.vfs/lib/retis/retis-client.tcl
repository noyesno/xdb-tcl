
proc ${NS}::connect {host port} {
  set ns [namespace current]

  set sock [socket $host $port]
  chan configure $sock -blocking 1 -encoding utf-8 -translation lf

  set client ${ns}::client@$sock
  set token [interp alias {} $client {} ${ns}::client $sock]
  @debug "alias token = $token"

  # TODO: use dbcmd from server response
  set dbcmd "${ns}::client::dbcmd@$sock"
  interp alias {} $dbcmd {} ${ns}::client::dbcmd $sock $client

  $client set -print 0

  return $dbcmd
}
