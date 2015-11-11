#!/usr/bin/env ruby


# Update Log List 
# Licensed under the GNU GPL
# (C)2008 Lucid Information Systems and Orion Transfer

# Lucid Information Systems 
# http://www.lucidsystems.org

# Orion Transfer
# http://www.oriontransfer.co.nz

#
# Written by Samuel Williams and Henri Shustak
# 


# About this script : 
# This script may be used to build a file containing a list of backup logs
# to scan with the backupscan.rb script.


# For more details on LBackup, visit the official website : 
# http://www.lucidsystems.org/tools/lbackup

# Quick Usage : ./updateloglist.rb -l output_loglist.txt -c output_configlist.txt


# Version history
# 1.0 : Initial Release
# 1.1 : Minor Bug Fixes (Improved parsing of the crontab)
# 1.2 : Major Bug Fixes (Actually reads something out of the crontab)
# 1.3 : Supports writting a second file to disk with a list of the paths to the configuration files (as specified within the crontab).
# 1.3 : Compatibilty fixes providing support for latest versions of ruby.

require "fileutils"
require 'optparse'

class String
    def bash_dump
        dump.gsub(/\\\\/, "\\")
    end
end

OPTIONS = {
  :log_list => "backuploglist.txt",
  :config_list => "backupconfiglist.txt",
}

ARGV.options do |o|
  script_name = File.basename($0)
  
  o.banner = "Usage: #{script_name} [options]"
  o.define_head "This script is used to build a file containg paths to backup logs."
  
  o.on("-l log_list", "--loglist config_list", "Output file with list of paths to backup logs") { |op| OPTIONS[:log_list] = op }
  o.on("-c config_list", "--conflist config_list", "Output file with list of paths to backup configurations") { |op| OPTIONS[:config_list] = op }
  
  o
end.parse!


# Pull in the lbackup configuration paths from the crontab
config_paths = IO.popen("crontab -l | grep -v -e \"^#\" | grep -w \"/usr/local/sbin/lbackup\" | awk -F \"/usr/local/sbin/lbackup \" '{print $2}'") do |io|
    io.readlines.collect { |p| p.strip }
end

log_paths = config_paths.collect { |p| 
    dir_name = File.dirname(p) 
    file_name = IO.popen("bash -c " + "source #{p.dump} ; echo \\$log_fileName".bash_dump) { |io| io.read.strip }
    dir_name + "/" + file_name
}

# Write those suckers out to disk overwriting anything that gets in the way.
File.open(OPTIONS[:log_list], "w") do |f|
    log_paths.each { |l| f.puts l }
end
File.open(OPTIONS[:config_list], "w") do |f|
    config_paths.each { |l| f.puts l }
end


