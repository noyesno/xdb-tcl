
proc main::tclinfo {args} {
  puts "loaded = [info loaded]"
  puts "tsv::handlers = [tsv::handlers]" 
  package require Thread

}
