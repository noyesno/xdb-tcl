
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

  @debug "reply_result = $reply_code $reply_body"
  return [list $reply_code $reply_body]
}

proc ${NS}::client::dbcmd {sock client args} {

  set cmd_argv [lassign $args cmd]

  if {$cmd eq "-print"} {
    $client set -print 1
    return
  }

  if {$cmd eq "close"} {
    catch {
      @debug "close $sock"
      ::close $sock
    }
    set ns [namespace current]
    set dbcmd "${ns}::dbcmd@$sock"
    interp alias {} $dbcmd {}
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
