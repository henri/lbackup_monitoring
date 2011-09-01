#!/usr/bin/env ruby


# Create a list of information such as directories which are being backed up.
# It is really a template to assist you with pulling the information you want in the format you want 
# from the contab.

# If you make a launchd compatible version then please consider submitting this to the LBackup project.
 
# Licensed under the GNU GPL
# (C)2010 Lucid Information Systems and Orion Transfer

# Lucid Information Systems 
# http://www.lucidsystems.org

# Orion Transfer
# http://www.oriontransfer.co.nz

#
# Written by Samuel Williams and Henri Shustak
# 


# About this script : 
# This script may be used to output a list of directories being backed up.


# For more details on LBackup, visit the official website : 
# http://www.lbackup.org

# Quick Usage : Using the example blelow, run this script as the user you want to scan the crontab for list of currently loaded backups 
# This command will not print out commented out crontab entries.
# command to run : ./list_contab_backup_information.rb

# To scan all crontabs create a wrapper script or modify this script.


# Version 1.1


# Version history
# 1.0 : Initial Release
# 1.1 : Updated some comments and information on usage.


require "fileutils"
require 'optparse'

class String
    def bash_dump
        dump.gsub(/\\\\/, "\\")
    end
end


# Pull in the lbackup configuration paths from the crontab
config_paths = IO.popen("crontab -l | grep -v -e \"^#\" | grep -w \"/usr/local/sbin/lbackup\" | awk -F \"/usr/local/sbin/lbackup \" '{print $2}'") do |io|
    io.readlines.collect { |p| p.strip }
end


log_paths = config_paths.collect { |p| 
    dir_name = File.dirname(p) 
    file_name = IO.popen("bash -c " + "source #{p.dump} ; echo \\$backupSource".bash_dump) { |io| io.read.strip }
    server_name = IO.popen("bash -c " + "source #{p.dump} ; echo \\$sshRemoteServer".bash_dump) { |io| io.read.strip }
    # list config file and what is being backed up : 
    dir_name + " : " + server_name + " : " + file_name
    # add in itmes or change the format as required.
}


log_paths.each { |l| puts l }


