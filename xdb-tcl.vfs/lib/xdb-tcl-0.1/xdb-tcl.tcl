
package require sqlite3

package provide xdb-tcl 0.1

package require retis

set NS xdb-tcl


namespace eval $NS {
  # variable dbcmd   ; array set dbcmd ""

  namespace eval service {}

  namespace eval server {
    variable dbcache [dict create query ""]

    namespace path [namespace parent]

    proc db_profile {sql ns} {
      set ms [expr {$ns/1000000}]
      @debug "sql profile = $ms ms # $sql"
    }
  }


  # proc debug {args} {
  #   # puts "debug: [join $args]"
  # }

}

retis::service ::${NS}::service


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

# TODO: purge stale sqlite dbcmd
proc ${NS}::purge {} {
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

proc ${NS}::server::cache {act pool args} {
  switch -- $act {
    "get" {
      lassign $args key varname
      upvar $varname value
      set value ""

      set cache_hit [::tsv::get $pool $key cached_value]

      if {!$cache_hit} {
        # Cache Miss
        return 0
      }

      lassign $cached_value value cache_mtime

      # XXX: At least 1 db file exist, and not newer than $cache_mtime

      set cache_expire 1

      try {
	foreach dbfile [list $pool $pool-wal] {
	  if [file exist $dbfile] {
	    set cache_expire 0
	    set db_mtime [file mtime $dbfile]

            # @debug "query cache check file mtime $db_mtime > $cache_mtime $dbfile"
            if { $db_mtime > $cache_mtime} {
              set cache_expire 1
	      break
            }
	  }
	}
      } on error err {
        @debug "query cache check error $err"
      }

      if {$cache_expire} {
        # Clear cache entry
        @debug "query cache clear $key@$cache_mtime from $pool"
        catch {
          ::tsv::unset $pool $key
        }
        return 0
      }

      return 1
    }
    "set" {
      lassign $args key value
      set now [clock seconds]
      ::tsv::set $pool $key [list $value $now]
    }
  } ;# end switch
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

  if {0 && [dict exist $dbcache query $dbfile $cachekey]} {
    set result [dict get $dbcache query $dbfile $cachekey]
    @debug "query result from cache"
    return $result
  }

  if [cache get $dbfile $cachekey result] {
    @debug "query result from cache $dbfile"
    return $result
  } else {
    set result [db_query $dbcmd $kargs(-sql) {*}[array get kargs]]

    # debug "update query cache = $result"
    # dict set dbcache query $dbfile $cachekey $result
    cache set $dbfile $cachekey $result
  }

  return $result
}

proc ${NS}::server::db_query {dbcmd sql args} {
  variable dbcache
  upvar kargs kargs

  @debug "db_query [array get kargs]"

   set result [list]
   set header [list]
   dict with kargs(-bind) {
     set nrow 0
     if {$kargs(-filter) eq ""} {
       set result [$dbcmd eval $sql]
     } else {
       $dbcmd eval $sql row {
	 if {$nrow==0} {
	   set columns $row(*)
	   unset row(*)
	   incr nrow
	 }

	 try {

	   if {$kargs(-filter) ne ""} {
	     set record [::apply [list {} "upvar row $kargs(-each) ; $kargs(-filter)"] ]
	   } else {
	     set record [array get row]
	   }

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
	   @debug "Error: $err"
	   return -code error $err
	 }

       }
     }
   }

   return $result
}


#----------------------------------------------------------------------#
# service command
#----------------------------------------------------------------------#

set NS retis::service

proc ${NS}::use {session dbfile args} {

    set dbcmd [::xdb-tcl::server::db_open $dbfile]

    # $dbcmd profile ${ns}::db_profile ;# TODO: move to db_open

    $session set dbcmd $dbcmd
    return [$session reply $dbfile]
}

proc ${NS}::query {session args} {
  set dbcmd [$session get dbcmd]
  set result [::xdb-tcl::server::do_db_query $dbcmd {*}$args]
  return [$session reply $result]
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

