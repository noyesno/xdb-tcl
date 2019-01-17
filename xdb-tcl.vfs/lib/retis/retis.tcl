#----------------------------------------------------------------------#
# retis = Remote Tcl Intepreter Server                                 #
#----------------------------------------------------------------------#

package provide retis 0.1

set NS retis

namespace eval retis {
  variable clients [dict create]

  namespace eval session {
    namespace path [namespace parent]
  }

  namespace eval server {
  }

  namespace eval service {
  }

  proc service {path} {
    ::apply [list path {
      namespace path [ linsert [namespace path] end $path]
    } ::retis::service ] $path
  }
}

set dir [file dir [info script]]

# TODO: make them packages
source [file join $dir retis-server.tcl]
source [file join $dir retis-client.tcl]
source [file join $dir retis-session.tcl]
source [file join $dir retis-service.tcl]

source [file join $dir protocol retis-sized.tcl]
source [file join $dir protocol retis-redis.tcl]
source [file join $dir protocol retis-comm.tcl]
source [file join $dir protocol retis-telnet.tcl]

#----------------------------------------------------------------------#
# entry                                                                #
#----------------------------------------------------------------------#


