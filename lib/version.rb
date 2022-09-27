#!/usr/bin/env ruby

COMMANDS = ['major', 'minor', 'patch']

regex = /^([0-9]+)\.?([0-9]*)\.?([0-9]*)/

version = ARGV[0]
command = ARGV[1]

unless ARGV.size > 1 or version =~ regex
  puts 'Usage: upgrade.rb <version> <command>'
  puts
  puts 'Commands:'
  puts "\tmajor\tUpgrade major number"
  puts "\tminor\tUpgrade minor number"
  puts "\tpatch\tUpgrade patch number"
  puts
  puts 'Example:'
  puts "\tupgrade.rb 1.3.5 minor"
  exit 1
end

parts = version.scan(regex)
parts = parts.first
parts.map! { |i| i.to_i }

major = parts[0]
minor = parts[1]
patch = parts[2]

if command == COMMANDS[0]
  major += 1
  minor = 0
  patch = 0
elsif command == COMMANDS[1]
  minor += 1
  patch = 0
else
  patch += 1
end

puts "#{major}.#{minor}.#{patch}"
