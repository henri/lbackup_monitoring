#!/usr/bin/env ruby


# Backup Scan 
# Licensed under the GNU GPL
# (C)2008 Lucid Information Systems and Orion Transfer

# Lucid Information Systems 
# http://www.lucidsystems.org

#
# Written by Samuel Williams and Henri Shustak
# 

# Version 2.3



# About this script : 
#
# This script is to be installed onto a backup server. It is designed scan
# LBackup log files and report errors found within these log files.
#
# A text file called "backuploglist.txt" then needs to be created within the
# same directory as backupscan. This file should then be loaded with the log
# files to be scanned. At this point you may run the script to query this 
# server for a summary of the backup logs which were in the text file.
# This process may be automated by a centralized server which checks multiple
# servers and presents the results in a palatable format.
# Later versions of this script require a second list of assosiated
# configuration files. The line numbers in these two files are assumed to
# corrispond with each other.
#
# Known issues : 
#    (1) This script is compatible with ruby 1.8 later versions of ruby
#        may not support the option parsing appraoch used within this script 
#        Ruby 2.1 should resolve this problem.
#    (2) Backup errors may be more than the number of backup log files being
#        scanned, this is to ensure that backup logs exceeding limits are
#        detected. This should be improved in a future version.
#    (3) Many of the checks performed are implemented using extremely wasteful
#        algorithms. Patches to optimize the checks, particularly relating 
#        to those which search for successful backup initiations would be
#        warmly welcomed.
#    (4) Assumes that the backup log is actually in chronological order and 
#        not corrupted. Perhaps a check sum for the backup log would
#        be a good idea.
#    (5) Some of the output could well be improved. Including all errors 
#        being reported, regardless of another error being reported
#        and taking error priority?
#

# Version Changes
# 
# v1.1 initial release.
# v1.2 various fixes.
# v1.3 adds details the date of the last backup to the output.
# v1.4 adds a check for backups which have not taken place within a set period.
# v1.5 last backup initiated time is accurate, backups which start and stop due to a lock file are ignored.
# v1.6 minor bug fixes.
# v1.7 improved error reporting.
# v1.8 additional details for full path reports.
# v1.9 check for in backup in progress lock file for improved reporting.
# v2.0 include the count of backups exceeding limits within the error count.
# v2.1 includes checks which work with LBackup 0.9.8r5 and later for checking the backup duration is within specified limits.
# v2.2 includes checks which confirm that the initiation time of the most recent successful backup (assuming one exists) is within specified initiated limits.
# v2.3 minor improvements to reporting.

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
#   Note - This should be changed to a default and then the command line could be configured to overide.
#          More details on number of seconds in various divisions of time are availible at : http://www.epochconverter.com
#          This feature may need to actually included in the backup configuration to allow per backup configuration.
#          This limit value is also used to confirm that the most recently successfully completed backup 
#          was started within this time. This is done to ensure that the previous successful backup is within
#          specified limits.
@max_number_of_seconds_since_previous_backup_initiated = "604800" # 86400 seconds is one day. 604800 is one week.


# Backup duration time limits (time that a backup may run for before being flagged as taking too long).
#   Note - This should be changed to a default and then the command line could be configured to overide.
#          More details on number of seconds in various divisions of time are availible at : http://www.epochconverter.com
#          This feature may need to actually included in the backup configuration to allow per backup configuration.
@max_number_of_seconds_for_backup_duration = "151200" # 302400 seconds is 12 hours. 151200 is 6 hours.

#puts log_paths.inspect

# Some varibles to keep track of the number of logs and backup directories we will be checking
logs_checked = 0
logs_with_errors = 0
backups_in_progess = 0
backup_lock_file_name = %x{cat /usr/local/sbin/lbackup | grep -e "^backup_lock_file_name=" }.split("\"")[1].chomp
@line_reference = 0
@backups_not_initiated_within_specified_limit = 0
@backups_duration_exceeding_specified_limit = 0
@current_ruby_time = Time.parse(`date`) # alterantivly you could use 'Time.now'
@current_backup_initiation_time_exceeds_specified_limit = "NO"
@current_backup_initiation_time_successfully_determined_from_log_file = "NO"
@current_backup_duration_exceeds_specified_limit = "NO"
@current_backup_duration_successfully_determined = "NO"
@current_backup_duration_unable_to_detemrin_duration_message = ""
@current_backup_duration_exceeded_message = ""
@current_backup_duration_in_seconds = 0
@current_backup_last_succesful_backup_initiation_time_determined_from_log_file = "NO"
@current_backup_last_succesful_backup_initiation_time_exceeds_specified_limit = "NO"
@succesful_backups_not_initiated_within_specified_limit = 0
@configuration_lock_error_message = "ERROR! : Backup configuration lock file present : "
@most_resent_backup_completed_sucssfully = "NO"

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


def check_and_display_last_backup (path)
   # provides reporting of information regarding the last backup.
   @current_backup_initiation_time_successfully_determined_from_log_file = "YES"
   # Scan for three lines (output from this script 'backupscan.rb' has had blank lines removed).
   last_backup_entry_information = `grep -x -A 3 "##################" "#{path}" | tail -n 1 | cut -c 1-50`
   if ( last_backup_entry_information.chomp != @configuration_lock_error_message.chomp ) then
       # The last backup log message is not an error regarding lock files
       last_backup_date = `grep -x -A 1 "##################" "#{path}" | tail -n 1`
   else
       # The last backup log message is an error regarding lock file. 
       # Attempt to locate the last backup start point which is not an error relating to lock files
       backup_initiations_parsed_with_grep = `grep -x -A 3 "##################" "#{path}"`
       backup_initiations = backup_initiations_parsed_with_grep.split(/^-{2}/)
       # We will sort in reverse and will go with the first one we find as the most recent backup initiation
       backup_initiations.reverse!
       current_backup_initiation = 0
       backup_initiations.each { |backup_initiation|
           if not backup_initiation.match(/^#{@configuration_lock_error_message}/) then
               # This backup did not have an associated lock file error so it is the most recent
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
   puts "Most recent backup initiated at : #{last_backup_date}"
   last_backup_ruby_time = Time.parse(last_backup_date)
   seconds_since_last_backup = @current_ruby_time.to_i - last_backup_ruby_time.to_i
   if seconds_since_last_backup.to_i > @max_number_of_seconds_since_previous_backup_initiated.to_i then
       @backups_not_initiated_within_specified_limit = @backups_not_initiated_within_specified_limit + 1
       @current_backup_initiation_time_exceeds_specified_limit="YES"
       mm, ss = seconds_since_last_backup.divmod(60)
       hh, mm = mm.divmod(60)
       dd, hh = hh.divmod(24)
       puts "                      %d days, %d hours, %d minutes ago" % [dd, hh, mm, ss]
   end
end


def check_and_display_last_succesful_backup (path)
   @current_backup_last_succesful_backup_initiation_time_determined_from_log_file = "YES"
   @current_backup_last_succesful_backup_initiation_time_exceeds_specified_limit = "NO"
   # Scan for three lines (output from this script 'backupscan.rb' has had blank lines removed).
   #last_succesful_backup_entry_information = `cat "#{path}"| sed -n '1!G;h;$p' | sed -n '/^Backup Completed Successfully/,$p' | sed -n '1!G;h;$p' | grep -x -A 3 "##################" | tail -n 1 | cut -c 1-50`
   last_succesful_backup_entry_information = `if [ \`grep -n -e '^Backup Completed Successfully' "#{path}" | wc -l | awk '{print $1}'\` -ge 2 ] ; then linesplit=$(grep -n -e '^Backup Completed Successfully' "#{path}" | cut -d: -f1 | tail -2 | head -1) ; cat "#{path}" | sed -n "$((linesplit+1))"',$p' | sed -n '1!G;h;$p' | sed -n '/^Backup Completed Successfully/,$p' | sed -n '1!G;h;$p' ; else cat "#{path}" | sed -n '1!G;h;$p' | sed -n '/^Backup Completed Successfully/,$p' | sed -n '1!G;h;$p' ; fi | grep -x -A 3 "##################" | tail -n 1 | cut -c 1-50`
   if ( last_succesful_backup_entry_information.chomp != @configuration_lock_error_message.chomp ) then
       # The last backup log message is not an error regarding lock files
       if ( last_succesful_backup_entry_information.chomp != "" ) then 
	       last_backup_date = `if [ \`grep -n -e '^Backup Completed Successfully' "#{path}" | wc -l | awk '{print $1}'\` -ge 2 ] ; then linesplit=$(grep -n -e '^Backup Completed Successfully' "#{path}" | cut -d: -f1 | tail -2 | head -1) ; cat "#{path}" | sed -n "$((linesplit+1))"',$p' | sed -n '1!G;h;$p' | sed -n '/^Backup Completed Successfully/,$p' | sed -n '1!G;h;$p' ; else cat "#{path}" | sed -n '1!G;h;$p' | sed -n '/^Backup Completed Successfully/,$p' | sed -n '1!G;h;$p' ; fi | grep -x -A 1 "##################" | tail -n 1`
	       if ( "#{last_backup_date.chomp}" == "" ) then
	           # Unable to find any successful backups. Suspect that there are no successful backups recorded in the log file
   	           @current_backup_last_succesful_backup_initiation_time_determined_from_log_file = "NO"
   	           @current_backup_last_succesful_backup_initiation_time_exceeds_specified_limit = "YES"
	       end
	   else
	   	    # Unable to find any successful backups. Suspect that there are no successful backups recorded in the log file
	       @current_backup_last_succesful_backup_initiation_time_determined_from_log_file = "NO"
	       @current_backup_last_succesful_backup_initiation_time_exceeds_specified_limit = "YES"
	   end
   else
       # The last backup log message relating to successful backup initiation is an error regarding lock file. 
       # Attempt to locate the last backup start point which is not an error relating to lock files
       backup_initiations_parsed_with_grep = `if [ \`grep -n -e '^Backup Completed Successfully' "#{path}" | wc -l | awk '{print $1}'\` -ge 2 ] ; then linesplit=$(grep -n -e '^Backup Completed Successfully' "#{path}" | cut -d: -f1 | tail -2 | head -1) ; cat "#{path}" | sed -n "$((linesplit+1))"',$p' | sed -n '1!G;h;$p' | sed -n '/^Backup Completed Successfully/,$p' | sed -n '1!G;h;$p' ; else cat "#{path}" | sed -n '1!G;h;$p' | sed -n '/^Backup Completed Successfully/,$p' | sed -n '1!G;h;$p' ; fi | grep -x -A 3 "##################"`
       backup_initiations = backup_initiations_parsed_with_grep.split(/^-{2}/)
       # We will sort in reverse and will go with the first one we find as the most recent backup initiation
       backup_initiations.reverse!
       current_backup_initiation = 0
       backup_initiations.each { |backup_initiation|
           if not backup_initiation.match(/^#{@configuration_lock_error_message}/) then
               # This backup did not have an associated lock file error so it is the most recent
               break 
           end
           current_backup_initiation += 1
       }
       # Locate the last successful backup date from the current_backup_initiation
       last_backup_date = `echo "#{backup_initiations[current_backup_initiation]}" | grep -x -A 1 "##################" | tail -n 1`
       if current_backup_initiation > backup_initiations.length then
           last_backup_date = "Unable to determine from information within the log file."
           @current_backup_last_succesful_backup_initiation_time_determined_from_log_file = "NO"
           @current_backup_last_succesful_backup_initiation_time_exceeds_specified_limit = "YES"
       end
   end
   if ( "#{@current_backup_last_succesful_backup_initiation_time_determined_from_log_file.chomp}" == "YES" ) then
       puts "Previous succesful backup initiated at : #{last_backup_date}"
       last_succesful_backup_ruby_time = Time.parse(last_backup_date)
       seconds_since_last_backup = @current_ruby_time.to_i - last_succesful_backup_ruby_time.to_i
       if seconds_since_last_backup.to_i > @max_number_of_seconds_since_previous_backup_initiated.to_i then
           @succesful_backups_not_initiated_within_specified_limit = @succesful_backups_not_initiated_within_specified_limit + 1
           @current_backup_last_succesful_backup_initiation_time_exceeds_specified_limit = "YES"
           mm, ss = seconds_since_last_backup.divmod(60)
           hh, mm = mm.divmod(60)
           dd, hh = hh.divmod(24)
           puts "                                         %d days, %d hours, %d minutes ago" % [dd, hh, mm, ss]
        end
    end
end



def check_if_backup_duration_exceeeds_specified_limit
  if @current_backup_duration_in_seconds > @max_number_of_seconds_for_backup_duration.to_i then
    @current_backup_duration_exceeds_specified_limit = "YES"
    @backups_duration_exceeding_specified_limit = @backups_duration_exceeding_specified_limit + 1
    return -1
  else
    @current_backup_duration_exceeds_specified_limit = "NO"
    return 0
  end
end


def check_log_for_last_succesful_backup_duration_entry (lines)
  # look into the log file two lines up and check the reported "Time elapsed in seconds"
  # if the backup is not succesfull or is in progress then this function will not be called.
  # Max number of seconds has a limit set (eg. is not set to zero)
  if lines[-2].match(/^Time elapsed in seconds /).to_s.length > 0 then
    elapsed_time_recorded_within_log_file=lines[-2].match(/\d+/)
	if ( ( elapsed_time_recorded_within_log_file.to_s.to_i >= 1 ) && ( elapsed_time_recorded_within_log_file.to_s != "" ) && ( lines[-2].to_s != "WARNING! : Unable to calculate the total time required for sucesfull backup.")) then
	  @current_backup_duration_in_seconds = elapsed_time_recorded_within_log_file.to_s.to_i
	  if ( @current_backup_duration_in_seconds.is_a? Integer ) then
	    @current_backup_duration_successfully_determined = "YES"
	    @current_backup_duration_exceeded_message = "Backup appears to be successful. However, the last backup was in progress for too long."
		return check_if_backup_duration_exceeeds_specified_limit
	  end
	end
  end
  @current_backup_duration_unable_to_detemrin_duration_message = "WARNING! : Unable to determine elapsed time for last succesful backup from the log file."
  @current_backup_duration_successfully_determined = "NO"
  @current_backup_duration_exceeds_specified_limit = "YES"
  @backups_duration_exceeding_specified_limit = @backups_duration_exceeding_specified_limit + 1
  return -1
end


def check_in_progress_backup_duration (absolute_path_to_backup_lock_file)
  # rather than using ps to find the process start time or the creation time on the lock file,
  # we will rely upon the time data stored within the lock file.
  @current_backup_duration_successfully_determined = "YES"
  start_time_since_epoch = %x{cat \"#{absolute_path_to_backup_lock_file}\" | head -n 1 | tail -n 1 | awk -F \" : \" '{print $2}'}.chomp.to_i
  if ( start_time_since_epoch <= 0 || start_time_since_epoch.to_s == "" ) then
    @current_backup_duration_unable_to_detemrin_duration_message = "WARNING! : Unable to detemin backup in progress backup start time by examining the lock file."
    @current_backup_duration_successfully_determined = "NO"
    @backups_duration_exceeding_specified_limit = @backups_duration_exceeding_specified_limit + 1
    return -1
  end
  if ( start_time_since_epoch.is_a? Integer ) then
    current_backup_duration_in_seconds = @current_ruby_time.to_i - start_time_since_epoch.to_i
    if ( @current_backup_duration_in_seconds.to_i <= 0 || @current_backup_duration_in_seconds.to_s == "" ) then
      @current_backup_duration_unable_to_detemrin_duration_message = "WARNING! : Unable to calculate the in progress backup duration by examining the lock file."
      @current_backup_duration_successfully_determined = "NO"
      @current_backup_duration_exceeds_specified_limit = "YES"
      return -2
    end
    if (( current_backup_duration_in_seconds.is_a? Integer ) && ( current_backup_duration_in_seconds.to_i >= 1 )) then
      @current_backup_duration_in_seconds = current_backup_duration_in_seconds
      @current_backup_duration_successfully_determined = "YES"
      @current_backup_duration_exceeded_message = "Backup appears to be in progress. Also, this backup has been in progress for too long."
      return check_if_backup_duration_exceeeds_specified_limit
    else
      @current_backup_duration_unable_to_detemrin_duration_message = "WARNING! :  Unable to calculate the in progress backup duration by examining the lock file."
      @current_backup_duration_successfully_determined = "NO"
      @current_backup_duration_exceeds_specified_limit = "YES"
      return -3
    end
  else
    @current_backup_duration_unable_to_detemrin_duration_message = "WARNING : Unable to calculate the in progress backup duration by examining the lock file."
    @current_backup_duration_successfully_determined = "NO"
    @current_backup_duration_exceeds_specified_limit = "YES"
    return -4
  end
end


log_paths.each do |p|
    unless p.match(/^\s*(#.*)?$/) # Do not deal with lines that commented out or blank
        @most_resent_backup_completed_sucssfully == "NO"
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
            @most_resent_backup_completed_sucssfully = "YES" # although not necessarily within the specified duration limits.
	        check_log_for_last_succesful_backup_duration_entry(lines)
            check_and_display_last_backup(p)
            if ( "#{@current_backup_initiation_time_exceeds_specified_limit}" == "YES" ) then
                puts "Backup appears to be successful. However, last backup was started to long ago."
                # This next line will incriment the error count when the backup initiation time limit is exceeded.
                logs_with_errors+=1
            elsif ( "#{@current_backup_last_succesful_backup_initiation_time_exceeds_specified_limit}" == "YES" ) then
                # If the backup was started too long ago this is not going to be reported due to the else. One error is enough to flag up a problem at this point.
            	puts "Backup appears to be successful. However, last succesfull backup was started to long ago."
                # This next line will incriment the error count when the backup initiation time limit is exceeded.
                logs_with_errors+=1
            else
                # If the backup was started too long ago this is not going to be reported due to the else. One error is enough to flag up a problem at this point.
                if @current_backup_duration_exceeds_specified_limit.to_s == "YES" then
                  if @current_backup_duration_successfully_determined == "NO" then
     				  puts "#{@current_backup_duration_unable_to_detemrin_duration_message}"
     				  puts "Backup appears to be successful." 
                  else
                      puts "#{@current_backup_duration_exceeded_message}"
                  end
                  # This next line will increment the error count when the backup duration time limit is exceeded.
                  logs_with_errors+=1
                else
                  puts "Backup appears to be successful." 
                end
            end
        else
			report_full_paths(p)
			# add a check to find the last initiation of a successful backup.... done and have commented out the checks for last display and check of backup. 
            check_and_display_last_succesful_backup(p)
            check_and_display_last_backup(p)
            log_path_parent_dir = File.dirname(p)
            absolute_path_to_backup_lock_file = log_path_parent_dir + "/" + backup_lock_file_name
            rsync_is_running = %x{ps -A | grep lbackup | grep "#{@config_paths[@line_reference]}" | grep -v \"grep\" | wc -l | awk '{print $1}'}
            if ( ( File.exist?(absolute_path_to_backup_lock_file) ) && ( rsync_is_running != 0 ) ) then
                check_in_progress_backup_duration(absolute_path_to_backup_lock_file)
                if @current_backup_duration_exceeds_specified_limit.to_s == "YES" then
                  if @current_backup_duration_successfully_determined == "NO" then
     				  puts "#{@current_backup_duration_unable_to_detemrin_duration_message}"
                  else
                      puts "#{@current_backup_duration_exceeded_message}"
                  end
                  logs_with_errors+=1
                elsif ( "#{@current_backup_last_succesful_backup_initiation_time_exceeds_specified_limit}" == "YES" ) then
                    # As this backup is in progress without exceeding any limits we will now check to see if there is a previous successful backup and if it is within initiation limits.
                	# If the backup was started too long ago this is not going to be reported due to the else. One error is enough to flag up a problem at this point.
            		puts "Last succesfull backup was started to long ago."
                	# This next line will incriment the error count when the successful backup initiation time limit is exceeded.
                	logs_with_errors+=1
                end
                puts "Backup appears to be in progress."
                backups_in_progess+=1
             else
             	# Just a single error will be reported in this situation. Enough to flag a problem with the backup.
                puts "Backup log indicates errors : "
                lines.each { |l| puts "\t#{l}" }
                logs_with_errors+=1
             end
         end
         logs_checked+=1
    end
    @current_backup_initiation_time_exceeds_specified_limit = "NO"
    @current_backup_duration_exceeds_specified_limit = "NO"
    @current_backup_last_succesful_backup_initiation_time_exceeds_specified_limit = "NO"
	@line_reference+=1
end

puts ""
puts ""
puts "=" * 72
puts "Summary : #{logs_checked} log files scanned. #{logs_with_errors} logs with errors. #{backups_in_progess} backups in progeess."
if @backups_not_initiated_within_specified_limit > 0 then
   puts ""
   puts "          A total of #{@backups_not_initiated_within_specified_limit} backup(s) have not been"
   puts "          initiated recently enough to comply with specified limits," 
   puts "          these contribute to the count of backups with errors."
   puts ""
end
if @succesful_backups_not_initiated_within_specified_limit > 0 then
   puts ""
   puts "          A total of #{@succesful_backups_not_initiated_within_specified_limit} sucesfull backup(s) have not been"
   puts "          initiated recently enough to comply with specified limits," 
   puts "          these contribute to the count of backups with errors."
   puts ""
end
if @backups_duration_exceeding_specified_limit > 0 then
    puts ""
    puts "          A total of #{@backups_duration_exceeding_specified_limit} backup(s) are exceeding the specified"
    puts "          limits for backup duration time, these contribute"
    puts "          to the count of backups with errors."
    puts ""
end

puts "=" * 72
puts ""
puts ""

