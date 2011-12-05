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

require ('yaml')
yml = YAML.load_file( options[:config] )
if options[:debug] or (yml['debug'] == true)
  auth = yml['auth_debug']
  puts 'Using auth_debug credentials.'
  options[:debug] = true
else
  auth = yml['auth']
end

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

require 'configbot/bghandler'
require 'configbot/confighandler'
require 'configbot/configbot_commands'

if (File.exist?(auth['pidfile']))
  pf = File.open(auth['pidfile'], "r")
  old_pid = pf.readline
  old_pid.strip!
  old_pid= Integer(old_pid)
  pf.close
end
if (old_pid)
  pn = `ps -p #{old_pid}`
  if (pn.include?("conf") or pn.include?("ruby"))
    pgid = `ps -p #{old_pid} -o pgid | tail -1`
    pgid.strip!
    `kill -15 -#{pgid}`
    `sleep 1`
  end
end

# Now let's write the pid of the watching process
pf = File.open(auth['pidfile'], "w")
pf.puts($$)
pf.close

if (File.exist?(auth['pidfile']))
  pf = File.open(auth['pidfile'], "r")
  old_pid = pf.readline
  old_pid.strip!
  old_pid =Integer(old_pid)
  pf.close
  if old_pid != $$
    Process.exit(0)
  end
end

### Let the children do what they do best ###

# Set resource appropriately
if auth['resource'] == 'hostname'
  resource = `/bin/hostname`
  resource = resource.downcase.chomp()
  if resource.match(/\./)
    resource = resource.split(".")[0]
  end
else
  resource = auth['resource']
end

# The cred's we need to talk to the jabber server
jid      = "#{auth['jid']}/#{resource}"
puts jid
module HiBot
  class ConfigHandler < HiBot::BotHandler
    def newSession( jid, muc )
      session = super( jid, muc )
      if jid.strip == 'tims@uahirise.org' || jid.strip == 'kfine@uahirise.org'
        session.newRS(HiBot::CommandResponseHandler)
      elsif jid.strip == @auth_info[:admin_muc_jid]
        session.newRS(HiBot::MUCResponseHandler)
      end
      return session
    end
  end
end

# How do we act on incoming messages?
msg_handler = HiBot::ConfigHandler.new(
  jid,
  auth['password'],
  auth['server'],
  auth['primary_muc_jid']
  )
msg_handler.on_exception{begin; msg_handler.cleanup; rescue Exception => e; puts "Whoa, There was an error: #{e.message}"; ensure; Process.exit; end}

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

if options[:debug]

  muc_session = msg_handler.getSession( auth['primary_muc_jid'] )
  muc_session = msg_handler.getSession( "#{auth['primary_muc_jid']}/tim" )

  print "running load watcher ... \n"
  # Test the load watching abilities of the bot
  load_watcher = LoadWatch.new( delayTime=60, session=muc_session )
  print "done setting up watches... \n"

end

# Stop the main thread and just process events
begin
  Thread.stop
ensure
  if (File.exist?(auth['pidfile']))
    pf = File.open(auth['pidfile'], "r")
    old_pid = pf.readline
    old_pid.strip!
    old_pid = Integer(old_pid)
    pf.close
    if old_pid == $$
      File.delete(auth['pidfile'])
    end
  end
end

