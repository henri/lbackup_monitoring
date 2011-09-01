#!/usr/bin/env ruby

#
# Version 1.0
# (C)2008 Lucid Information Systems
# Licenced under the GNU GPL
# www.lucidsystems.org
#

require 'optparse'

OPTIONS = {
  :host_list => "host_list.txt"
}

ARGV.options do |o|
  script_name = File.basename($0)
  o.banner = "Usage: #{script_name} [options]"
  o.define_head "This script is used to aggregate log information from various servers."
  o.on("-h host_list", "File containing a list of hosts to check in with") { |OPTIONS[:host_list]| }
  o
end.parse!

hosts = File.readlines(OPTIONS[:host_list]).collect{ |p| p.strip }

hosts.each do |h|
  
  h.match("([^\t]+)\t(.*)$")
  address = $1
  exe = $2
  system("ssh", address, exe)
  
end
