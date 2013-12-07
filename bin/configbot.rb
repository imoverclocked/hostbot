#!/usr/bin/env ruby

require ('optparse')
options = {}
optparse = OptionParser.new do|opts|
  opts.banner = "Usage: configbot [options]"
  options[:config] = '/etc/configbot/conf/main.yaml'
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
require 'configbot/configbot_commands'

class LoadWatch < BGHandler::CronHandler
  def run()
    output = `uptime`
    if $? == 0
      # mach_load = output.gsub(/.*load average: /).split(' ').shift.to_f
      mach_load = output.gsub(/.*load average[s]*: /, '').gsub(/,/, '').split(",").shift.to_f
      if mach_load > 10
        self.getSession().say("Load alert #{mach_load}!")
      end
    else
    end
  end
end

conf = HiBot::BotConfig.new( options[:config], options[:debug] )
conf.pidfile
conf.connect
