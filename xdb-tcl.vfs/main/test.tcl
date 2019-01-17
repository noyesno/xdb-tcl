
proc main::test {args} {
  package require tcltest
  ::tcltest::configure -verbose {pass}
  # ::tcltest::workingDirectory ./run-test
  # uplevel #0 { namespace import ::tcltest::* }

  lassign $args tclfile

  if [file isfile $tclfile] {
    uplevel #0 source $tclfile
  } elseif [file isdir $tclfile] {
    ::tcltest::configure -testdir $tclfile
    ::tcltest::runAllTests
  }
  exit
}

