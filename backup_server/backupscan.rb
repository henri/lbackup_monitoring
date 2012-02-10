#!/usr/bin/env ruby


# Backup Scan 
# Licensed under the GNU GPL
# (C)2008 Lucid Information Systems and Orion Transfer

# Lucid Information Systems 
# http://www.lucidsystems.org

#
# Written by Samuel Williams and Henri Shustak
# 

# Version 1.8



# About this script : 
#
# This script is to be installed onto a backup server. It is designed scan
# LBackup log files and report errors found within these log files.
#
# A text file called "backuploglist.txt" then needs to be created within the
# same directory as backupscan. This file should then be loaded with the log
# files to be scanned. At this point you may run the script to query this 
# server for a summary of the backup logs which were in the text file.
# This process may be automated by a centralized server which checks multiple
# servers and presents the results in a palatable format.

# Version Changes
# 
# v1.1 initial release.
# v1.2 various fixes.
# v1.3 adds details the date of the last backup to the output.
# v1.4 adds a check for backups which have not taken place within a set period.
# v1.5 last backup initiated time is accurate. Backups which start and stop due to a lock file are ignored.
# v1.6 minor bug fixes.
# v1.7 improved error reporting.
# v1.8 additional details for full path reports.

require 'fileutils'
require 'optparse'
require 'time'

OPTIONS = {
  :log_list => "backuploglist.txt",
  :config_list => "backupconfiglist.txt",
}

ARGV.options do |o|
  script_name = File.basename($0)
  
  o.banner = "Usage: #{script_name} [options]"
  o.define_head "This script is used to aggregate log information."
  
  o.on("-l log_list", "File containing a list of paths to backup log files") { |OPTIONS[:log_list]| }
  o.on("-c config_list", "File containg a list of paths to backup configuration files") { |OPTIONS[:config_list]| }
  
  o
end.parse!

# load the input lists
begin
  log_paths = File.readlines(OPTIONS[:log_list]).collect{ |p| p.strip }
  @config_paths = File.readlines(OPTIONS[:config_list]).collect{ |p| p.strip }
rescue => msg
  # ("+msg+")"
  puts "    ERROR! : Unable to read one or more of the input files which were specified"
  puts "             Please confirm that both of the follow input files exist."
  puts ""
  puts "             log_list    :   #{OPTIONS[:log_list]}"
  puts "             config_list :   #{OPTIONS[:config_list]}"
  puts ""
  puts "             Further assistance with the setup of the monitoring system is availible"
  puts "             from the following URL : http://www.lbackup.org/monitoring_multiple_backup_logs"
  exit -1
end

# check these lists are the same length
if log_paths.length != @config_paths.length then
  puts "    ERROR! : Input files differ in length please check the input list files are valid."
  exit -1
end

# Internal Options

# Backup initiated time limits (time that may pass since last backup started before flagged as overdue).
#   Note - This should be changed to a default and then the command line could be configured to overide this issue.
#          More details on number of seconds in various divisions of time are availible at : http://www.epochconverter.com
#          This feature may need to actually included in the backup configuration to allow per backup configuration.
@max_number_of_seconds_since_previous_backup_initiated = "604800" # 86400 seconds is one day. 604800 is one week.

#puts log_paths.inspect

# Some varibles to keep track of the number of logs we check
logs_checked = 0
logs_with_errors = 0
@line_reference = 0
@backups_not_initiated_within_specified_limit = 0
@current_ruby_time = Time.parse(`date`) # alterantivly you could use 'Time.now'
@current_backup_initiation_time_exceeds_specified_limit="NO"
@current_backup_initiation_time_successfully_determined_from_log_file="NO"

def report_full_paths (path)
    # additional calcualtions for full path report output
    backup_destination_path = `echo "source \\"#{@config_paths[@line_reference]}\\" ; echo \\${backupDest}" | bash`
    if ( backup_destination_path == "" ) then 
        backup_destination_path = "ERROR! : Unable to determin backup destination path, manual inspection of the configuration file is required."
    end
    # reports some paths (hopefully absolute) for realivent files and direcotries.
	puts "       Configuration path : #{@config_paths[@line_reference]}"
    puts "         Destination path : #{backup_destination_path}"
    puts "                 Log path : #{path}"
end

def display_last_backup (path)
   # provides reporting of information regarding the last backup.
   @current_backup_initiation_time_successfully_determined_from_log_file = "YES"
   configuration_lock_error_message = "ERROR! : Backup configuration lock file present : "
   # Scan for three lines (output from this script 'backupscan.rb' has had blank lines removed).
   last_backup_entry_information = `grep -x -A 3 "##################" "#{path}" | tail -n 1 | cut -c 1-50`
   if ( last_backup_entry_information.chomp != configuration_lock_error_message.chomp ) then
       # The last backup log message is not an error regarding lock files
       last_backup_date = `grep -x -A 1 "##################" "#{path}" | tail -n 1`
   else
       # The last backup log message is an error regarding lock file. 
       # Attempt to locate the last backup start point which is not an error relating to lock files
       backup_initiations_parsed_with_grep = `grep -x -A 3 "##################" "#{path}"`
       backup_initiations = backup_initiations_parsed_with_grep.split(/^-{2}/)
       # We will srot in reverse and will go with the first one we find as the most recent backup initiation
       backup_initiations.reverse!
       current_backup_initiation = 0
       backup_initiations.each { |backup_initiation|
           if not backup_initiation.match(/^#{configuration_lock_error_message}/) then
               # This backup did not have an assosiated lock file error so it is the most recent
               break 
           end
           current_backup_initiation += 1
       }
       # Locate the last backup date from the current_backup_initiation
       last_backup_date = `echo "#{backup_initiations[current_backup_initiation]}" | grep -x -A 1 "##################" | tail -n 1`
       if current_backup_initiation > backup_initiations.length then
           last_backup_date = "Unable to determine from information within the log file."
           @current_backup_initiation_time_successfully_determined_from_log_file = "NO"
       end
   end
   puts "Backup initiated at : #{last_backup_date}"
   last_backup_ruby_time = Time.parse(last_backup_date)
   seconds_since_last_backup = @current_ruby_time.to_i - last_backup_ruby_time.to_i
   if seconds_since_last_backup > @max_number_of_seconds_since_previous_backup_initiated.to_i then
       @backups_not_initiated_within_specified_limit = @backups_not_initiated_within_specified_limit + 1
       @current_backup_initiation_time_exceeds_specified_limit="YES"
       mm, ss = seconds_since_last_backup.divmod(60)
       hh, mm = mm.divmod(60)
       dd, hh = hh.divmod(24)
       puts "                      %d days, %d hours, %d minutes ago" % [dd, hh, mm, ss]
   end
   if @current_backup_initiation_time_successfully_determined_from_log_file == "NO" then
      @backups_not_initiated_within_specified_limit = @backups_not_initiated_within_specified_limit + 1
      @current_backup_initiation_time_exceeds_specified_limit="YES"
   end
end

log_paths.each do |p|
    unless p.match(/^\s*(#.*)?$/) # Do not deal with lines that commented out or blank
        puts "=" * 72
        puts "Inspecting most recent backup log #{File.basename(p)}"
        lines = `tail -n 50 #{p}`.strip.split(/\r|\n/).delete_if {|l| l.length == 0 } 
        if lines.size == 0
			report_full_paths(p)
            if File.readable?(p) then 
                puts "WARNING! : Backup log is empty."
            else
                puts "WARNING! : Backup log is unable to be opened for examination."
            end
            logs_with_errors+=1
        elsif lines[-1].match /Backup Completed Successfully/
            display_last_backup(p)
            if "#{@current_backup_initiation_time_exceeds_specified_limit}" == "YES" then
                puts "Backup appears to be successful. However, last backup was too long ago."
            else
                puts "Backup appears to be successful."
            end
        else
			report_full_paths(p)
            display_last_backup(p)
            puts "Backup log indicates error:"
            lines.each { |l| puts "\t#{l}"}
            logs_with_errors+=1
        end
        logs_checked+=1
    end
    @current_backup_initiation_time_exceeds_specified_limit="NO"
	@line_reference+=1
end

puts ""
puts ""
puts "=" * 72
puts "Summary : #{logs_checked} log files scanned. #{logs_with_errors} logs with errors."
if @backups_not_initiated_within_specified_limit > 0 then
   puts ""
   puts "          A total of #{@backups_not_initiated_within_specified_limit} backup(s) have not been initiated recently"
   puts "          enough to comply with specified limits."
   puts ""
end
puts "=" * 72
puts ""
puts ""

