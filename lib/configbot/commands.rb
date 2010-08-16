#
# A framework and implementation of Commands with ACLs
#

require 'configbot/acl.rb'

module BotCommands

  # Static class
  class CommandList
    @@commands = {}       # Hash of Class => instances
    @@commandsByName = {} # Hash of name  => Class

    # accessor methods
    def self.commands; @@commands; end
    def self.commandsByName; @@commandsByName; end

    # replaces previously known commands with later defined commands
    def self.addCommandClass( newClass )
      if ! @@commands[ newClass ]
        newCommand = newClass.new( {}, nil )
        newCommandName = newClass.command_name()

        oldClass = @@commandsByName[ newCommandName ]
        if oldClass != nil
          @@commands.delete( oldClass )
        end

        print "Adding command: #{newCommand}\n"

        @@commands[ newClass ] = newCommand
        @@commandsByName[ newCommandName ] = newClass
      end
    end
  end

  class Command
    class << self
      attr_accessor :command_name
      attr_accessor :short_desc
      attr_accessor :help_text
      attr_accessor :acl
      attr_accessor :handlePrivately
      attr_reader   :procs

      def handlePrivately?(text)
        return @handlePrivately
      end

      def addProc( instance )
        @procs ||= []
        # Sloppy cleanup of commands
        @procs.each { |p| p.destroy if ! p.thread }
        @procs.push( instance ) if ! @procs.include?( instance )
        @procs.compact!
      end
      def delProc( instance )
        @procs ||= []
        @procs.delete( instance )
        @procs.compact!
      end
      def getProc( id )
        @procs.each { |process| return process if "#{process.object_id}" == id }
        return nil
      end
    end

    attr_reader :session
    attr_reader :thread  ## The thread this command runs in
    attr_reader :acl_criteria

    def initialize( acl_criteria, session )
      @acl_criteria = acl_criteria
      @session = session
      if self.class.handlePrivately == nil
        self.class.handlePrivately = true
      end
      @finish = false
      Command.addProc( self )
      # print "My identity: ", self.class.command_name, "\n"
    end

    def destroy
      Command.delProc( self )
    end

    def to_s()
      who = "(nil)"
      who = @session.target_jid if @session
      return "#{self.object_id} #{who} #{self.class.command_name} (#{self.class})"
    end

    def finish()
      print "#{self.class} received finish ... \n"
      @finish = true
    end
    def finish?()
      @finish
    end

    ## Override from other Command Subclasses
    # run should not return until all processing is done. This means that any threads created
    # should be finished before returning.
    def run(text)
      say("Run method not implemented for this command")
    end

    def say(text)
      @session.say( text )
    end

    def can?( acl_criteria )
      return self.class.acl.can?( acl_criteria )
    end
    def might?( acl_criteria )
      return self.class.acl.might?( acl_criteria )
    end

    # Some commands may want to override this to say something
    def permissionDenied()
      # EG: say( "#{@command_name}: permission denied" )
      # say( "permission denied" )
    end

    # Run method in a try/catch style and report the exception (if any)
    def exec(text, wait = false)
      begin
        if ! can?( @acl_criteria )
          return permissionDenied()
        end
      rescue Exception=>e
        e_string = "ACL Issues ... not continuing to run command: #{e}"
        print e_string
        say( e_string )
        return
      end
      @thread = Thread.new {
        begin
          self.run(text)
        rescue Exception=>e
          e_string = "Caught exception: #{e}\n"
          print e_string
          print e.backtrace.join("\n"), "\n"
          say( e_string )
        end
        # Once the command is done ... it is done
        self.destroy
      }
      @thread.join if wait
    end

  end

################################################################################
# Common command implementations ###############################################
################################################################################

  class BotKillCommand < Command
    self.command_name = 'bkill'
    self.acl = BotCommands.admin_acl
    self.short_desc = 'kill a bot process'
    self.help_text = 'bkill [-no-destroy] <id> - attempts to stop a bot process with the specified id'
    CommandList.addCommandClass( BotKillCommand )

    def run(text)
      text[ self.class.command_name ] = ""
      args = text.split
      opts = { :destroy => true }
      opts[:destroy] = false if args.include?( "-no-destroy" )
      args.delete("-no-destroy")
      args.each { |pid|
        process = Command.getProc( pid )
        if process
          thread = process.thread
          thread.kill if thread
          process.destroy if opts[:destroy]
        end
      }
    end
  end

  class BotPSCommand < Command
    self.command_name = 'bps'
    self.acl = BotCommands.any_acl
    self.short_desc = 'internal bot process listing'
    self.help_text = 'bps - lists running bot processes'
    CommandList.addCommandClass( BotPSCommand )

    def run(text)
      running = Command.procs
      output = "Running processes: \n"
      running.each { |proc| output += "#{proc}\n" } 
      say( output )
    end
  end

  class ExitCommand < Command
    self.command_name = 'exit'
    self.acl = BotCommands.admin_acl && BotCommands.private_acl
    self.short_desc = 'ask a bot to exit'
    self.help_text = 'exit - for use when the bot is mis-behaving'
    self.handlePrivately = false
    CommandList.addCommandClass( ExitCommand )

    def run(text)
      session().cleanup( text )
    end
  end


  class HelpCommand < Command
    self.command_name = 'help'
    self.acl = BotCommands.private_acl
    self.short_desc = 'provides help on various commands'
    self.help_text = 'help {command} provides detailed help on a command'
    CommandList.addCommandClass( HelpCommand )

    def help_on_topic(topic)
      if CommandList.commandsByName.include?(topic)
        say CommandList.commandsByName[topic].help_text 
      else
        say( "help on #{topic} is not yet implemented" )
      end
    end

    def general_help()
      commands = BotCommands::CommandList.commandsByName.keys
      ret_text = "known commands:"
      commands.sort.each { |command_name|
        class_name = BotCommands::CommandList.commandsByName[ command_name ]
	ret_text += "\n#{command_name} -- #{class_name.short_desc}"
      }
      say( ret_text )
    end

    def run(text)
      keywords = text.split
      keywords.shift
      if keywords.length > 0
        keywords.each { |topic|
          help_on_topic(topic)
        }
      else
        general_help()
      end
    end
  end

  # Quick class to wrap a session and prepend rid={id} to all responses
  class IDSessionWrapper
    def initialize( realSession, id )
      @realSession = realSession
      @id = id
    end

    # Pre-pend rid={id} to all output
    def say( *args )
      args[0] = "rid=#{@id} #{args[0]}"
      @realSession.say( *args )
    end

    # Wrap any other commands directly
    def method_missing( name, *args )
      @realSession.send( name, *args )
    end
  end

  class IDCommand < Command
    self.command_name = 'id'
    self.acl = BotCommands.private_acl
    self.short_desc = 'provides an id to track commands'
    self.help_text = 'id {number} {command} -- provides output prefixed with rid={number} for a command'
    self.handlePrivately = false
    CommandList.addCommandClass( IDCommand )

    # Wrap another command if we are allowed to run the command
    def run( text )
      start_time = Time.now
      commandArgs = text.split
      commandArgs.shift # Get rid of "id"

      opts = {
        :keepAlive => false,
        :finMsg => true
        }

      id = commandArgs.shift # Get the ID we want to prepend
      wrapper = IDSessionWrapper.new( @session, id )

      # Send keep-alive messages to let the watching process know we are
      # still alive
      keep_alive = Thread.new {
        while true do
          sleep(10)
          wrapper.say( "keep-alive" )
        end
      }

      commands = BotCommands::CommandList.commandsByName
      action = commands[ commandArgs[0] ]
      if action
        command = action.new( acl_criteria(), wrapper )
        command.exec(commandArgs.join(" "), wait=true)
      end

      # Don't need to keep sending these...
      keep_alive.kill
      elapsed_time = Time.now - start_time
      wrapper.say( "fin wall_time=#{elapsed_time * 1000}" )
    end
  end

  class PingCommand < Command
    self.command_name = 'ping'
    self.acl = BotCommands.any_acl
    self.short_desc = 'respond if asked correctly'
    self.help_text = 'ping <resource> - responds if <resource> matches'
    CommandList.addCommandClass( PingCommand )

    def run(text)
      if text == "ping #{@session.client.jid.resource}"
        say("pong")
      elsif text =~ /^ping .*#{@session.client.jid.resource}.*/
        say("pong!")
      elsif text =~ /^ping .*#{@session.client.jid.resource.split(".").shift}.*/
        say("pong!!")
      end
    end
  end

  class VersionCommand < Command
    self.command_name = 'version'
    self.acl = BotCommands.any_acl
    self.short_desc = 'respond if specified version does not match'
    self.help_text = 'version <version> - responds if <version> does not match'
    self.handlePrivately = false
    CommandList.addCommandClass( VersionCommand )

    def run(text)
      if text != "version #{HiBot.CONFIGBOT_VERSION}"
        # say("Version on #{@session.client.jid.resource} is: #{HiBot.CONFIGBOT_VERSION}")
        say("#{HiBot.CONFIGBOT_VERSION}")
      end
    end
  end

end
