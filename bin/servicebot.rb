#!/usr/bin/env ruby

require ('optparse')
options = {}
optparse = OptionParser.new do|opts|
  opts.banner = "Usage: servicebot [options]"
  options[:config] = '/etc/configbot/conf/service.yaml'
  opts.on( '-c f', '--config=f', '--config f', 'configuration file' ) do|f|
    options[:config] = f
    puts "using configuration: #{f}"
  end
  options[:debug] = false
  opts.on( '-d', '--debug', 'debug mode' ) do
    options[:debug] = true
  end
  opts.on( '-h', '--help', 'Display this screen' ) do
    puts opts
    exit
  end
end
optparse.parse!

dev_append = ""
if options[:debug]
  # Assume we are running the bot as one of:
  #   ../bin/configbot.rb -d
  $:.insert(0, ".")
  #   ./bin/configbot.rb -d
  $:.insert(0, "lib")
  #   ./configbot.rb -d
  $:.insert(0, "../lib")
  print "Running as a develoment bot...\n"
end

require 'configbot/conf'
# require 'configbot/configbot_commands'
require 'configbot/service_commands'

conf = HiBot::BotConfig.new( options[:config], options[:debug] )
conf.resource = conf.debug ? "dev-service-#{conf.resource}" : "service-#{conf.resource}"
conf.pidfile
conf.connect
