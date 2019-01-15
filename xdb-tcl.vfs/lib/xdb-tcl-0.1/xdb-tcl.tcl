
package require sqlite3

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

proc ${NS}::client::send_command {sock body} {
  set body [encoding convertto utf-8 $body]

  set size [string length $body]
  puts -nonewline $sock "\$$size\r\n"
  puts -nonewline $sock "$body\r\n"
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
    set reply_code [string range $line 1 end-1]

    set line [gets $sock]
    set size [string range $line 1 end-1]
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

  send_command $sock [list $cmd {*}$req_argv]

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

  switch -- [$client get protocol] {
    "comm" {
      set reply_id 0
      puts $sock [list reply $reply_id [list return -code 0 $body]]
      flush $sock
    }
    "redis" {
      set body [encoding convertto utf-8 $body]
      set size [string length $body]

      puts -nonewline $sock "*2\r\n"
      puts -nonewline $sock "+ok\r\n"
      puts -nonewline $sock "\$$size\r\n"
      puts -nonewline $sock "$body\r\n"
      flush $sock
    }
    "sized" {
      set size [string length $body]
      puts $sock $size
      puts $sock $body
      flush $sock
    }
    "telnet" {
      set body [encoding convertto utf-8 $body]
      set size [string length $body]

      puts $sock "+OK $size"
      puts $sock $body
      puts $sock "."
      flush $sock
    }
    default {
      "not supported"
    }
  }

  watchdog start $client
  return
}

proc ${NS}::server::reply_error {client body} {
  set sock [$client sock]

  switch -- [$client get protocol] {
    "comm" {
      set reply_id 0
      puts $sock [list reply $reply_id [list return -code 1 $body]]
      flush $sock
    }
    "redis" {
      set body [encoding convertto utf-8 $body]

      set size [string length $body]
      puts -nonewline $sock "*2\r\n"
      puts -nonewline $sock "+error\r\n"
      puts -nonewline $sock "\$$size\r\n"
      puts -nonewline $sock "$body\r\n"
      flush $sock
    }
    "telnet" {
      set body [encoding convertto utf-8 $body]
      set size [string length $body]

      puts $sock "+ERR $size"
      puts $sock $body
      puts $sock "."
      flush $sock
    }
    default {
      "not supported"
    }
  }
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

proc ${NS}::server::do_db_query {dbcmd sql args} {
  variable dbcache

  set dbfile [dict get $dbcache dbcmd  $dbcmd  dbfile]
  set mtime  [dict get $dbcache dbfile $dbfile mtime]

  if {[file mtime $dbfile] > $mtime} {
    # TODO: fine grain control
    dict unset dbcache query $dbfile
  }

  # command = -sql -var -filter -bind
  #         | -sql -bind

  array set kargs {
    -sql    ""
    -bind   ""
    -filter ""
    -each   "row"
  }
  set kargs(-sql) $sql
  array set kargs $args



  set cachekey [list $kargs(-sql) $kargs(-bind) $kargs(-filter)]

  if {[dict exist $dbcache query $dbfile $cachekey]} {
    set result [dict get $dbcache query $dbfile $cachekey]
    debug "query result from cache"
    return $result
  }

  set result [db_query $dbcmd $kargs(-sql) {*}[array get kargs]]

  dict set dbcache query $dbfile $cachekey $result

  return $result
}

proc ${NS}::server::db_query {dbcmd sql args} {
  variable dbcache
  upvar kargs kargs

  debug "db_query [array get kargs]"

   set result [list]
   set header [list]
   dict with kargs(-bind) {
     set nrow 0
     $dbcmd eval $sql row {
       if {$nrow==0} {
         set columns $row(*)
         unset row(*)
         incr nrow
       }

       try {
         set record [::apply [list {} "upvar row $kargs(-each) ; $kargs(-filter)"] ]

         # if {$nrow==1} {
         #   set header $columns
         #   lappend result $header
         # }

         lappend result $record
       } on continue {} {
         continue
       } on break {} {
         break
       } on error err {
         debug "Error: $err"
         return -code error $err
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

  if {$cmd eq "ping"} {
    return [reply_result $client "pone $cmd_argv"]
  }

  if {$cmd eq "use"} {
    set dbfile [lindex $args 1]

    set dbcmd [db_open $dbfile]

    $dbcmd profile ${ns}::db_profile ;# TODO: move to db_open

    $client set dbcmd $dbcmd
    return [reply_result $client $dbfile]
  }

  switch -- $cmd {
    "insert" {
      # TODO:
    }
    "select" {
      # TODO:
    }
    "delete" {
      # TODO:
    }

    "eval" {
      # do tcl eval
    }

    "query" {
      set dbcmd [$client get dbcmd]
      set result [do_db_query $dbcmd {*}$cmd_argv]
    }

    "apply" {
      set apply_argv [lassign $cmd_argv apply_args apply_body]
      set result [::apply [list $apply_args $apply_body] {*}$apply_argv]
    }
  }

  return [reply_result $client $result]
}


proc ${NS}::server::listen {port} {
  set ns [namespace current]

  set ssock [socket -server [list ${ns}::server::accept] $port]

  debug "listen $port ..."
}

proc ${NS}::server::accept {sock client_addr client_port {cleanup ""}} {
  debug "accept $client_addr:$client_port"

  fconfigure $sock -blocking 0 -encoding binary -translation binary

  set ns  [namespace current]
  set pns [namespace parent]
  set client ${pns}::client@$sock
  interp alias {} $client {} ${pns}::client $sock

  $client set sock $sock
  $client set ncmd 0

  set timeout 10  ;# 10 seconds
  $client set watchdog [list $timeout ${ns}::forget $client]
  watchdog start $client

  fileevent $sock readable [list ${ns}::read_command $sock $client]


  if {$cleanup ne ""} {
    vwait ${ns}::forever

    debug "cleanup $cleanup"
    uplevel 1 $cleanup
  }
}

proc ${NS}::server::watchdog {act client} {

  set timer [$client get watchdog]

  switch -- $act {
    "start" {
      debug "watch dog start $timer"
      ::after {*}[$client get watchdog]
    }
    "stop" {
      debug "watch dog stop $timer"
      ::after cancel [lindex [$client get watchdog] 1]
    }
    "feed" {
      ::after cancel [lindex [$client get watchdog] 1]
      ::after {*}[$client get watchdog]
    }
  }
}

# TODO: or use name `drop`
proc ${NS}::server::forget {client} {
  set sock [$client sock]
  debug "forget client $client"
  $client close
  interp alias {} $client {}
  close $sock

  set ns [namespace current]
  set ${ns}::forever 0
}

proc ${NS}::server::read_telnet {sock client args} {
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
    forget $client
    return
  }

  return
}

proc ${NS}::server::read_comm {sock client} {
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
    forget $client
    return
  }
}

proc ${NS}::server::read_redis {sock client args} {

  if {[llength $args]==0} {
    set line [gets $sock]
  } else {
    set line [lindex $args 0]
  }

  if {[string index $line 0] eq "$"} {
    set size [string range $line 1 end]
    set command [read $sock $size]
    gets $sock
  } elseif {[string index $line 0] eq "*"} {
    set n [string range $line 1 end]
    set command [list]
    while {$n} {
      incr n -1
      gets $sock line
      set size [string range $line 1 end]
      set arg [read $sock $size]
      gets $sock
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
    forget $client
    return
  }

  debug "request = $size $command"
  execute $client {*}$command
}

proc ${NS}::server::read_sized {sock client args} {
  if {[llength $args]==0} {
    set size [gets $sock]
  } else {
    set size [lindex $args 0]
  }

  if {$size eq ""} {
    if {[eof $sock]} {
      forget $client
      return
    }
  }

  debug "size = $size"
  set command [read $sock $size]
  gets $sock
  debug $size $command
  execute $client {*}$command
}

proc ${NS}::server::read_command {sock client} {
  set ncmd [$client get ncmd]

    watchdog stop $client

    set line [gets $sock]

    set ntoks 0
    catch { set ntoks [llength $line] }

    if { $ntoks==2
      && [string is integer -strict [lindex $line 0 0]]
      && [string is integer -strict [lindex $line 1]]
       } {
      $client set protocol "comm"
      fconfigure $sock -encoding utf-8 -translation lf
      puts $sock "{ver 3}"
      set ns [namespace current]
      fileevent $sock readable [list ${ns}::read_comm $sock $client]
      return
    } elseif {[string index $line 0] eq "*" || [string index $line 0] eq "$"} {
      $client set protocol "redis"
      set ns [namespace current]
      fconfigure $sock -translation binary -encoding binary
      fileevent $sock readable [list ${ns}::read_redis $sock $client]
      read_redis $sock $client $line
      return
    } elseif {[string is integer -strict $line]} {
      $client set protocol "sized"
      set ns [namespace current]
      fconfigure $sock -translation lf -encoding utf-8
      fileevent $sock readable [list ${ns}::read_sized $sock $client]
      read_sized $sock $client $line
    } elseif {$line ne ""} {
      $client set protocol "telnet"
      set ns [namespace current]
      fconfigure $sock -translation {auto binary} -encoding utf-8
      fileevent $sock readable [list ${ns}::read_telnet $sock $client]
      read_telnet $sock $client $line
      return
    } else {
      # TODO: not expected
    }

  return
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

