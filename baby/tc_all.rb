require "rbconfig"
system "#{Config::CONFIG['bindir']}/ruby big.rb"
system "#{Config::CONFIG['bindir']}/ruby basic.rb"
system "#{Config::CONFIG['bindir']}/ruby perf.rb"
