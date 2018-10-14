

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
  set dbcmd "${ns}::dbcmd@$sock"
  interp alias {} $dbcmd {} ${ns}::dbcmd $sock $client

  $client set -print 0

  return $dbcmd
}

proc ${NS}::filter_argv {argv argwant {argkeys ""}} {
    set kargv [list]
    set argv_left [list]

    for { set argidx 0 ; set argc [llength $argv] } {$argidx<$argc} {incr argidx} {
      set arg [lindex $argv $argidx]
      if {$arg in $argwant} {
        lappend kargv $arg [lindex $argv [incr argidx]]
      } else {
        lappend argv_left $arg
      }
    }

    foreach key $argkeys value $argv_left {
      if {$key ne "" && $key in $argwant} {
        lappend kargv $key $value
      }
    }

    return $kargv
}

proc ${NS}::parse_argv {argv argwant {argkeys ""}} {
    set kargs [dict create]
    set argv_left [list]

    for { set argidx 0 ; set argc [llength $argv] } {$argidx<$argc} {incr argidx} {
      set arg [lindex $argv $argidx]
      if {$arg in $argwant} {
        dict set kargs $arg [lindex $argv [incr argidx]]
      } else {
        lappend argv_left $arg
      }
    }

    foreach key $argkeys value $argv_left {
      if {$key ne "" && $key in $argwant} {
        dict set kargs $key $value
      }
    }

    foreach key $argwant {
      dict append kargs $key  ;# create if missing
    }

    return $kargs
}

proc ${NS}::dbcmd {sock client args} {


  set cmd_argv [lassign $args cmd]

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

  set req_argv $cmd_argv

  if {$cmd eq "query"} {
    set req_argv [filter_argv $cmd_argv {-filter -bind -sql} {-sql -body}]
  }

  request $sock [list $cmd {*}$req_argv]

  # TODO: check eof
  set size   [gets $sock]
  set req_result [read $sock $size]
  gets $sock

  set cmd_result $req_result

  if {$cmd eq "query"} {
    set req_kargs [parse_argv $cmd_argv {-as}]
    set cmd_result [format_query_result [dict get $req_kargs -as] $cmd_result]
  }

  if {[$client get -print]} {
    puts $cmd_result
  }
  return $cmd_result
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

proc ${NS}::do_db_query {dbcmd args} {
  variable dbcache

  set dbfile [dict get $dbcache dbcmd  $dbcmd  dbfile]
  set mtime  [dict get $dbcache dbfile $dbfile mtime]

  if {[file mtime $dbfile] > $mtime} {
    # TODO: fine grain control
    dict unset dbcache query $dbfile
  }

  array set kargs [parse_argv $args {-sql -bind -filter}]

  set cachekey [list $kargs(-sql) $kargs(-bind) $kargs(-filter)]

  if {[dict exist $dbcache query $dbfile $cachekey]} {
    set result [dict get $dbcache query $dbfile $cachekey]
    debug "query result from cache"
    return $result
  }

  set result [db_query $dbcmd $kargs(-sql) $kargs(-bind) $kargs(-filter)]

  dict set dbcache query $dbfile $cachekey $result

  return $result
}

proc ${NS}::db_query {dbcmd args} {
  variable dbcache

  lassign $args kargs(-sql) kargs(-bind) kargs(-filter)

   set result [list]
   set header [list]
   dict with kargs(-bind) {
     set nrow 0
     $dbcmd eval $kargs(-sql) row {
       switch -- [catch $kargs(-filter) record] {
         0 { # ok
           incr nrow
           if {$nrow==1} {
             set header $row(*)
             lappend result $header
           }
           set record [list]
           foreach col $header {
             lappend record [set row($col)]
           }
           lappend result $record
         }
         1 { # error
           return -code error $record
         }
         2 { # return
           lappend result $record
         }
         3 { # break
           break
         }
         4 { # continue
           continue
         }
       }
     }
   }

   return $result
}

proc ${NS}::format_query_result {as records} {

  set result $records

  if {$as eq "" || $as eq "table"} {
    return $result
  }

  set nrow 0
  set header ""
  set result ""
  foreach record $records {
    incr nrow
    if { $nrow==1 } {
      set header $record
      continue
    }

    switch -- $as {
      "flat" {
        # [
        #   $row_1_col_1, $row_1_col_2,
        #   $row_2_col_1, $row_2_col_2
        # ]
        lappend result {*}$record
      }
      "list" {
        # [
        #   [$row_1_col_1, $row_1_col_2],
        #   [$row_2_col_1, $row_2_col_2]
        # ]
        lappend result $record
      }
      "dict" {
        set newrec [dict create]
        foreach col $header val $record {
          dict set newrec $col $val
        }
        lappend result $newrec
      }
    }
  }

  return $result
}

proc ${NS}::execute {client args} {

  set sock [$client sock]

  set ns [namespace current]

  set cmd_argv [lassign $args cmd]

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
    set dbcmd [$client get dbcmd]
    set result [do_db_query $dbcmd {*}$cmd_argv]
  }


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

  set data [read $sock $size]
  gets $sock
  debug "request = $size $data"
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

