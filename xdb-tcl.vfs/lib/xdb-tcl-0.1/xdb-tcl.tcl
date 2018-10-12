

package require sqlite3

package provide xdb-tcl 0.1

set NS xdb-tcl

namespace eval $NS {
  variable clients ;# [dict create]
  # variable dbcmd   ; array set dbcmd ""
  variable dbcache [dict create]

  proc debug {args} {
    # puts "debug: [join $args]"
  }

  proc db_profile {sql ns} {
    set ms [expr {$ns/1000000}]
    debug "sql profile = $ms ms # $sql"
  }
}

# TODO: proc ${NS}::open

proc ${NS}::connect {host port} {
  set ns [namespace current]

  set sock [socket $host $port]
  fconfigure $sock -blocking 1 -encoding binary -translation binary

  set client ${ns}::client-$sock
  interp alias {} $client {} ${ns}::client $sock

  # TODO: use dbcmd from server response
  set dbcmd "${ns}::dbcmd-$sock"
  interp alias {} $dbcmd {} ${ns}::dbcmd $sock $client

  $client set -print 0

  return $dbcmd
}

proc ${NS}::dbcmd {sock client args} {


  set cmd [lindex $args 0]

  if {$cmd eq "-print"} {
    $client set -print 1
    return
  }

  if {$cmd eq "close"} {
    set ns [namespace current]
    set dbcmd "${ns}::dbcmd-$sock"
    interp alias {} $dbcmd {}
    close $sock
    return
  }



  request $sock $args

  # TODO: check eof
  set size   [gets $sock]
  set result [read $sock $size]
  gets $sock

  if {[$client get -print]} {
    puts $result
  }
  return $result
}

proc ${NS}::request {sock body} {
  set size [string length $body]
  puts $sock $size
  puts $sock $body
  flush $sock
  return
}

proc ${NS}::reply {client body} {
  set sock [$client sock]

  set size [string length $body]

  puts $sock $size
  puts $sock $body
  flush $sock
  return
}

proc ${NS}::client {sock act args} {
  variable clients

  switch -- $act {
    "sock" {
      return $sock
    }
    "set" {
      return [dict set clients $sock {*}$args]
    }
    "get" {
      return [dict get $clients $sock {*}$args]
    }
    "close" -
    "unset" {
      return [dict unset clients $sock]
    }
    default {
      return [dict $act $clients $sock {*}$args]
    }
  }
}

# TODO: purge stale sqlite dbcmd
proc ${NS}::purge {} {
  return
}

proc ${NS}::db_open {dbfile} {
  variable dbcache

  set now [clock seconds]

  if {![dict exist $dbcache dbfile $dbfile]} {
    set ns [namespace current]
    set cmd "${ns}::dbcmd[info cmdcount]"
    sqlite3 $cmd $dbfile -create false

    set timeout 3000
    $cmd timeout $timeout

    set mtime [file mtime $dbfile]
    dict set dbcache dbfile $dbfile [dict create dbcmd $cmd ctime $now atime $now mtime $mtime timeout $timeout]
    dict set dbcache dbcmd $cmd [list dbfile $dbfile]
  }

  set dbcmd [dict get $dbcache dbfile $dbfile dbcmd]
  dict set dbcache dbfile $dbfile atime $now
  dict set dbcache dbcmd  $dbcmd  atime $now

  return $dbcmd
}

# TODO:
proc ${NS}::db_read_cache {dbcmd args} {
}

proc ${NS}::db_query {dbcmd args} {
  variable dbcache

  set args [lassign $args sql]

  debug "dbcmd = $dbcmd , sql = $sql"


  set dbfile [dict get $dbcache dbcmd $dbcmd  dbfile]
  set mtime  [dict get $dbcache dbfile $dbfile mtime]

  if {[file mtime $dbfile] > $mtime} {
    # TODO: fine grain control
    dict unset dbcache query $dbfile
  }


  set argc [llength $args]

  set -bind ""
  set -key [list $sql]
  if {$argc==1 || $argc==3} {
    set -bind  [lindex $args end]
    set args   [lrange $args 0 end-1]
    lappend -key ${-bind}
  }

  if {[dict exist $dbcache query $dbfile ${-key}]} {
    set result [dict get $dbcache query $dbfile ${-key}]
    debug "query result from cache"
    return $result
  }

  if {[llength $args]==0} {
    debug "query without bind"
    dict with -bind {
      set result [$dbcmd eval $sql]
    }
  } elseif {[llength $args]==2} {
    debug "query with bind [set -bind]"
    set result ""
    dict with -bind {
      $dbcmd eval $sql {*}$args
    }
  } else {
    # TODO: Error
  }

  dict set dbcache query $dbfile ${-key} $result
  return $result
}

proc ${NS}::execute {client args} {

  set sock [$client sock]

  set ns [namespace current]

  set cmd [lindex $args 0]
  if {$cmd eq "use"} {
    set dbfile [lindex $args 1]

    set dbcmd [db_open $dbfile]

    $dbcmd profile ${ns}::db_profile ;# TODO: move to db_open

    $client set dbcmd $dbcmd
    return [reply $client $dbcmd]
  }

  if {$cmd eq "insert"} {
    # TODO:
  }
  if {$cmd eq "select"} {
    # TODO:
  }
  if {$cmd eq "delete"} {
    # TODO:
  }

  if {$cmd eq "eval"} {
    # do tcl eval
  }

  if {$cmd eq "query"} {
    set args [lrange $args 1 end]
  }

  set dbcmd [$client get dbcmd]
  set result [db_query $dbcmd {*}$args]

  return [reply $client $result]
}



proc ${NS}::listen {port} {
  set ns [namespace current]

  set ssock [socket -server [list ${ns}::accept] $port]

  debug "listen $port ..."
}

proc ${NS}::accept {sock client_addr client_port} {
  debug "accept $client_addr:$client_port"

  fconfigure $sock -blocking 0 -encoding binary -translation binary

  set ns [namespace current]
  set client ${ns}::client-$sock
  interp alias {} $client {} ${ns}::client $sock

  $client set sock $sock
  fileevent $sock readable [list ${ns}::read_command $client]
}

# TODO: or use name `drop`
proc ${NS}::forget {client} {
  set sock [$client sock]
  debug "forget client $client"
  $client close
  interp alias {} $client {}
  close $sock
}

proc ${NS}::read_command {client} {
  set sock [$client sock]

  set size [gets $sock]
  if {$size eq ""} {
    if {[eof $sock]} {
      forget $client
      return
    }
  }

  debug "size = $size"
  set data [read $sock $size]
  gets $sock
  debug $size $data
  execute $client {*}$data
}

return

  [+] support return error
  [+] find grain query cache
  [+] support delayed insert

  [+] multiple thread
  [+] multiple process

  [+] fallback to local sqlite3 dbcmd

  [+] support kv database leveldb
  [+] support redis
  [+] use project name sqldis?

