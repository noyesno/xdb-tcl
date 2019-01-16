# vim:set syntax=tcl sw=2: #

package require Thread

package provide socket 0.1

namespace eval socket {

  proc thread_error {thread_id errorInfo} {
    puts "Thread Error $thread_id: $errorInfo"
  }

  proc listen {port accept init} {
    set ssock [socket -server [list [namespace which accept] $accept $init] $port]

    puts "listen $port ..."

    thread::errorproc [namespace which thread_error]
  }

  proc accept {accept init sock client_addr client_port} {
    after idle [list [namespace which accept2thread] $accept $init $sock $client_addr $client_port]
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
