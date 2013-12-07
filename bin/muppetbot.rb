#!/usr/bin/env ruby

require ('optparse')
options = {}
optparse = OptionParser.new do|opts|
  opts.banner = "Usage: muppetbot [options]"
  options[:config] = '/etc/configbot/conf/muppet.yaml'
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
require 'configbot/configbot_commands'
require 'configbot/puppet_commands'

module HiBot

  class MuppetHandler < HiBot::BotHandler
    def newSession( jid, muc )
      session = super( jid, muc )
      jid_type = session.jid_type( jid )
      print "new session/response handler for #{jid} -- #{jid.strip} (#{jid_type})\n"
      if BotCommands.AdminJID.include?( "#{jid.strip}" )
        session.newRS(HiBot::MuppetCommandResponseHandler)
      elsif jid_type == :bot
        session.newRS(HiBot::AggregateResponseHandler)
      elsif jid_type == :muc
        session.newRS(HiBot::MuppetMUCResponseHandler)
      end
      print "Session: #{session}\n"
      return session
    end
  end

  ## MUPPET SPECIFIC IMPLEMENTATION ##
  class MuppetCommandResponseHandler < CommandResponseHandler
    def initialize (*args)
      super *args
      @acl_criteria.store(:bot_type, :muppetbot)
    end
  end

  class MuppetMUCResponseHandler < MUCResponseHandler
    def initialize( *args )
      super *args
      @acl_criteria.store(:bot_type, :muppetbot)
      # Hash of nick => DelayedNotifier
      @delayNotifiers = {}
    end

    # Watch for certains nodes to enter/exit the room
    def joinedRoom( nick )
      super( nick )
      if @delayNotifiers.key?(nick)
        @delayNotifiers.delete(nick).cancelled = true
      end
    end

    def leftRoom( nick )
      super( nick )
      if( watchNick?( nick ) )
        if ! @delayNotifiers.key?(nick)
	  @delayNotifiers[ nick ] = DelayedNotifier.new( 30 ) { say( "#{nick} left the room" ) }
	end
      end
    end

    def watchNick?( nick )
      if (nick =~ /cnode.*/ or nick =~ /opends.*/)
	     return true
		else
		  return false
		end
    end

  end

  class DelayedNotifier < BGHandler::DelayHandler
     attr_accessor :cancelled

     def initialize( delayTime, &block )
       super(delayTime, repeat=0, runTimeO=runTimeO)
       @block = block
       self.cancelled = false
     end

     def run()
       return if self.cancelled
       @block.call
     end
  end
####################################

end

conf = HiBot::BotConfig.new( options[:config], options[:debug] )
conf.resource = conf.debug ? "dev-pastor-#{conf.resource}" : "pastor-#{conf.resource}"
conf.pidfile
conf.connect(HiBot::MuppetHandler)

