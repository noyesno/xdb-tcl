
package provide xdb-tcl 0.1

set NS xdb-tcl

namespace eval $NS {
  variable clients [dict create]
  # variable dbcmd   ; array set dbcmd ""

  namespace eval client {
    namespace path [namespace parent]
  }

  namespace eval server {
    variable dbcache [dict create]

    namespace path [namespace parent]

    proc db_profile {sql ns} {
      set ms [expr {$ns/1000000}]
      debug "sql profile = $ms ms # $sql"
    }
  }


  proc debug {args} {
    # puts "debug: [join $args]"
  }

}

#----------------------------------------------------------------------#
# entry                                                                #
#----------------------------------------------------------------------#

proc ${NS}::listen {port} {
  package require sqlite3

  set ns [namespace current]

  set ssock [socket -server [list ${ns}::server::accept] $port]

  debug "listen $port ..."
}

proc ${NS}::connect {host port} {
  set ns [namespace current]

  set sock [socket $host $port]
  fconfigure $sock -blocking 1 -encoding binary -translation binary

  set client ${ns}::client@$sock
  interp alias {} $client {} ${ns}::client $sock

  # TODO: use dbcmd from server response
  set dbcmd "${ns}::client::dbcmd@$sock"
  interp alias {} $dbcmd {} ${ns}::client::dbcmd $sock $client

  $client set -print 0

  return $dbcmd
}

#----------------------------------------------------------------------#
# common                                                               #
#----------------------------------------------------------------------#

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

#----------------------------------------------------------------------#
# client                                                               #
#----------------------------------------------------------------------#

proc ${NS}::client::request {sock body} {
  set size [string length $body]
  puts $sock "\$$size"
  puts $sock $body
  flush $sock
  return
}

proc ${NS}::client::read_reply {sock} {
  set reply_code ""
  set reply_body ""

  # *2\r\n
  # +ok\r\n
  # $N\r\n
  # ...\r\n

  # TODO: check eof
  set line [gets $sock]
  if {[string index $line 0] eq "*"} {
    set line [gets $sock]
    set reply_code [string range $line 1 end]

    set line [gets $sock]
    set size [string range $line 1 end]
    set reply_body [read $sock $size]
    gets $sock
  }

  debug "reply_result = $reply_code $reply_body"
  return [list $reply_code $reply_body]
}

proc ${NS}::client::dbcmd {sock client args} {

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

  lassign [read_reply $sock] cmd_code cmd_result

  if {$cmd eq "query"} {
    set req_kargs [parse_argv $cmd_argv {-as}]
    set cmd_result [format_query_result [dict get $req_kargs -as] $cmd_result]
  }

  if {[$client get -print]} {
    puts $cmd_result
  }
  return $cmd_result
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

#----------------------------------------------------------------------#
# server                                                               #
#----------------------------------------------------------------------#

proc ${NS}::server::reply_result {client body} {
  set sock [$client sock]

  set size [string length $body]

  puts $sock "*2"
  puts $sock "+ok"
  puts $sock "\$$size"
  puts $sock $body
  flush $sock
  return
}

proc ${NS}::server::reply_error {client body} {
  set sock [$client sock]

  set size [string length $body]

  puts $sock "*2"
  puts $sock "+error"
  puts $sock "\$$size"
  puts $sock $body
  flush $sock
  return
}


proc ${NS}::server::db_open {dbfile} {
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
proc ${NS}::server::db_read_cache {dbcmd args} {
}

proc ${NS}::server::do_db_query {dbcmd args} {
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

proc ${NS}::server::db_query {dbcmd args} {
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

proc ${NS}::client::format_query_result {as records} {

  set result $records

  if {$as eq ""} {
    set as "list"
  }

  if {$as eq "table"} {
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

proc ${NS}::server::execute {client args} {

  set sock [$client sock]

  set ns [namespace current]

  set cmd_argv [lassign $args cmd]

  if {$cmd eq "use"} {
    set dbfile [lindex $args 1]

    set dbcmd [db_open $dbfile]

    $dbcmd profile ${ns}::db_profile ;# TODO: move to db_open

    $client set dbcmd $dbcmd
    return [reply_result $client $dbfile]
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

  if {$cmd eq "apply"} {
    set apply_argv [lassign $cmd_argv apply_args apply_body]
    set result [::apply [list $apply_args $apply_body] {*}$apply_argv]
  }

  return [reply_result $client $result]
}

proc ${NS}::server::accept {sock client_addr client_port} {
  debug "accept $client_addr:$client_port"

  fconfigure $sock -blocking 0 -encoding binary -translation binary

  set ns  [namespace current]
  set pns [namespace parent]
  set client ${pns}::client@$sock
  interp alias {} $client {} ${pns}::client $sock

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

proc ${NS}::server::read_command {client} {
  set sock [$client sock]

  set size [gets $sock]
  if {$size eq ""} {
    if {[eof $sock]} {
      forget $client
      return
    }
  }

  if {[string index $size 0] eq "$"} {
    set size [string range $size 1 end]
    set command [read $sock $size]
    gets $sock
  } elseif {[string index $size 0] eq "*"} {
    set n [string range $size 1 end]
    set command [list]
    while {$n} {
      incr n -1
      gets $sock line
      set size [string range $line 1 end]
      set arg [read sock $size]
      gets $sock
      lappend command $arg
    }
  } else {
    set command [read $sock $size]
    gets $sock
  }

  debug "request = $size $command"
  execute $client {*}$command
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

