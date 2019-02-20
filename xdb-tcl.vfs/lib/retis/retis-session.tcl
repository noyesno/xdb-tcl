#----------------------------------------------------------------------#
# Retis Session                                                        #
#----------------------------------------------------------------------#

proc ${NS}::session {sock act args} {
  variable clients

  set ns "[namespace current]::session"
  set session ${ns}@$sock


  switch -- $act {
    "new" {
      interp alias {} $session {} ${ns} $sock
      $session set self $session
      $session set sock $sock
      $session set ncmd 0
      return $session
    }
    "reply" {
      set result [lindex $args 0]
      return [${ns}::reply_result $session $result]
    }
    "sock" {
      return $sock
    }
    "set" {
      return [dict set clients $sock {*}$args]
    }
    "get" {
      return [dict get $clients $sock {*}$args]
    }
    "wait" {
      vwait $session!forever
      @debug "vwait $session!forever = [set $session!forever]"
    }
    "watchdog" {
      set watchdog_act [lindex $args 0]
      ${ns}::watchdog $watchdog_act $session
    }
    "close" {
      set reason [lindex $args 0]
      catch {
        ::close $sock
      }
      $session watchdog stop
      set $session!forever $reason
      set self [dict get $clients $sock self]
      interp alias {} $self {}  ;# Or use `rename $self ""`
      return [dict unset clients $sock]
    }
    default {
      return [dict $act $clients $sock {*}$args]
    }
  }
}

proc ${NS}::session::watchdog {act client} {

  set watchdog [$client get watchdog]
  lassign $watchdog time command

  switch -- $act {
    "start" {
      @debug "watch dog start $watchdog"
      ::after cancel $command
      ::after $time $command
    }
    "stop" {
      @debug "watch dog stop $watchdog"
      ::after cancel $command
    }
    "feed" {
      @debug "watch dog feed $watchdog"
      ::after cancel $command
      ::after $time $command
    }
  }
}

#----------------------------------------------------------------------#
# reply_result
#----------------------------------------------------------------------#

proc ${NS}::session::reply_result {client body} {
  set sock [$client sock]

  set protocol [$client get protocol]
  @debug "reply result ($protocol) [string length $body]"
  # debug "$body"

  switch -- $protocol {
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
      # set body [encoding convertto utf-8 $body]
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

  # $client watchdog start ;# do this in execute()
  return
}

#----------------------------------------------------------------------#
# reply_error
#----------------------------------------------------------------------#

proc ${NS}::session::reply_error {client body args} {
  set sock [$client sock]

  @debug "reply_error $body"

  switch -- [$client get protocol] {
    "sized" {
      set size [string length $body]
      puts $sock [list $size error]
      puts $sock $body
      flush $sock
    }
    "comm" {
      set reply_id 0
      puts $sock [list reply $reply_id [list return -code error $body]]
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

  # $client watchdog start ;# do this in execute()
  return
}

#----------------------------------------------------------------------#
# read_command
#----------------------------------------------------------------------#

proc ${NS}::session::read_command {sock client} {
  set ncmd [$client get ncmd]

    $client watchdog stop

    # FIXME: if below read command blocking, there will be an issue.

    set line [gets $sock]

    set ntoks 0
    catch { set ntoks [llength $line] }

    if { $ntoks==2
      && [string is integer -strict [lindex $line 0 0]]
      && [string is integer -strict [lindex $line 1]]
       } {
      $client set protocol "comm"
      chan configure $sock -encoding utf-8 -translation lf
      puts $sock "{ver 3}"
      set ns [namespace current]
      chan event $sock readable [list ${ns}::read_comm $sock $client]
      return
    } elseif {[string index $line 0] eq "*" || [string index $line 0] eq "$"} {
      $client set protocol "redis"
      set ns [namespace current]
      # XXX: Redis use "\r\n" as newline.
      #      Redis use byte count, -translation should be disabled.
      #      Redis itself use a binary encoding.
      #      In this package, `encoding convertto utf-8` is used before reply.
      chan configure $sock -translation binary -encoding binary
      chan event $sock readable [list ${ns}::read_redis $sock $client]
      read_redis $sock $client $line
      return
    } elseif {[string is integer -strict $line]} {
      $client set protocol "sized"
      set ns [namespace current]
      # XXX: "sized" use "\n" as new line. Use char count as mark.
      #      Encoding can be specified as utf-8. No conversion is needed for input and output.
      #      Use "auto" for input to handle the case of "\r\n"
      chan configure $sock -encoding utf-8 -translation {auto lf}
      chan event $sock readable [list ${ns}::read_sized $sock $client]
      read_sized $sock $client $line
    } elseif {$line ne ""} {
      $client set protocol "telnet"
      set ns [namespace current]
      # XXX: For telnet, convert char encoding to/from utf-8 for terminal display.
      #      Only support single line command.
      chan configure $sock -translation {auto lf} -encoding utf-8
      chan event $sock readable [list ${ns}::read_telnet $sock $client]
      read_telnet $sock $client $line
      return
    } elseif {[eof $sock]} {
      $client close "eof read_command"
      return
    } else {
      @debug "see empty response"
      # TODO: not expected
    }

  return
}

#----------------------------------------------------------------------#
# execute command
#----------------------------------------------------------------------#

proc ${NS}::session::execute {client args} {
  $client watchdog stop

  set sock [$client sock]

  set ns [namespace current]

  set cmd_argv [lassign $args cmd]

  set sns ::retis::service

  try {
    ${sns}::$cmd $client {*}$cmd_argv
  } on error err {
    reply_error $client $err $args
  } finally {
    $client watchdog start
  }
}

