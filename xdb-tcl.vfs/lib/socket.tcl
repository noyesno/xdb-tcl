# vim:set syntax=tcl sw=2: #

package require Thread

package provide socket 0.1

namespace eval socket {
  variable parallel

  proc thread_error {thread_id errorInfo} {
    puts "Thread Error $thread_id: $errorInfo"
  }

  proc listen {port accept args} {
    variable parallel

    if {"-tpool" in $args} {
      set init [lindex $args end]
      set parallel "tpool"
      tpool_init $init
    } elseif {"-thread" in $args} {
      set init [lindex $args end]
      set parallel "thread"
    }


    set ssock [socket -server [list [namespace which accept] $accept $init] $port]

    puts "listen $port ..."

    thread::errorproc [namespace which thread_error]
  }

  proc accept {accept init sock client_addr client_port} {
    variable parallel

    switch -- $parallel {
      "thread" {
        after idle [list [namespace which accept2thread] $accept $init $sock $client_addr $client_port]
      }
      "tpool" {
        after idle [list [namespace which accept2tpool]  $accept $init $sock $client_addr $client_port]
      }
    }
  }


  proc tpool_init {init} {
    variable tpool

    set    initcmd ""
    append initcmd "\n" [list vfs::mk4::Mount $::KIT_ROOT $::KIT_ROOT]
    append initcmd "\n" [list set ::auto_path $::auto_path]
    append initcmd "\n" $init

    # TODO: make -maxworkers configureable
    set tpool [tpool::create -maxworkers 128 -initcmd $initcmd]
  }

  proc accept2tpool {accept init sock client_addr client_port} {
    variable tpool

    thread::detach $sock

    set cleanup {
      # Do not exit thread. But may need cleanup.
    }

    set script ""
    append script "\n" [list thread::attach $sock]
    append script "\n" [list $accept $sock $client_addr $client_port $cleanup]

    tpool::post -nowait -detached $tpool $script
  }

  proc accept2thread {accept init sock client_addr client_port} {
    set tid [thread::create]
    thread::transfer $tid $sock

    thread::send -async $tid [list vfs::mk4::Mount $::KIT_ROOT $::KIT_ROOT]
    thread::send -async $tid [list set ::auto_path $::auto_path]
    thread::send -async $tid $init

    set cleanup {
      try {
        puts "debug: thread::release = [thread::release]"
      } on error err {
        puts "thread exit error $err"
      }
    }

    thread::send -async $tid [list $accept $sock $client_addr $client_port $cleanup] ::${tid}@result

    # trace add variable ::${tid}@result write
  }

}

return

set tpool [tpool::create]

