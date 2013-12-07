#!/usr/bin/env ruby

require 'yaml'
require 'configbot/bghandler'
require 'configbot/confighandler'

class PIDFileException < Exception
end

class ConfigParseException < Exception
end

module HiBot

  class BotConfig
    attr_reader :resource
    attr_reader :debug

    def initialize( yamlFile, debug = false )
      @yml = YAML.load_file( yamlFile )

      @debug = debug or @yml['debug']
      @auth = @yml['auth']
      if @debug && ! @yml['auth_debug'].nil?
        @auth = @yml['auth_debug']
        puts 'Using auth_debug credentials.'
      end

      # Set resource appropriately
      if @auth['resource'] == 'hostname'
        resource = `/bin/hostname`
        resource = resource.downcase.chomp()
        if resource.match(/\./)
          resource = resource.split(".")[0]
        end
      else
        resource = @auth['resource']
      end
      self.resource = resource
    end

    def resource=(res)
      @resource = res
      @jid      = "#{@auth['jid']}/#{@resource}"
      puts @jid
    end

    def pidfile( pidfilepath = @auth['pidfile'] )
      # just return the pidfile if we already have it
      @pidfile.nil? or return @pidfile
      # attempt to obtain a pidfile
      if (File.exist?(pidfilepath))
        pf = File.open(pidfilepath, "r")
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
      pf = File.open(pidfilepath, "w")
      pf.puts($$)
      pf.close

      if (File.exist?(pidfilepath))
        pf = File.open(pidfilepath, "r")
        old_pid = pf.readline
        old_pid.strip!
        old_pid =Integer(old_pid)
        pf.close
        if old_pid != $$
          raise PIDFileException, "Could not get a lock on the pidfile: #{pidfilepath}"
        end
      end
      @pidfile = pidfilepath
    end

    def connect(botClass = HiBot::BotHandler)
      # How do we act on incoming messages?
      @msg_handler = botClass.new(
        @jid,
        @auth['password'],
        @auth['server']
        )
      @msg_handler.on_exception{begin; @msg_handler.cleanup; rescue Exception => e; raise "Whoa, There was a fatal error!\n#{e.message}:\n#{e.backtrace}"; ensure; Process.exit; end}

      @debug and @msg_handler.debug()

      # Ingest the rest of the main.yaml file
      ingestACLs(@yml['acls'])
      ingestCMDACLs(@yml['cmds'])
      joinMUCs(@yml['join_mucs'])
      includeSubConf(@yml['include'])

      # Stop the main thread and just process events
      begin
        Thread.stop
      ensure
        if (File.exist?(@pidfile))
          pf = File.open(@pidfile, "r")
          old_pid = pf.readline
          old_pid.strip!
          old_pid = Integer(old_pid)
          pf.close
          if old_pid == $$
            File.delete(@pidfile)
          end
        end
      end
    end

    # Set special ACLs by name
    def ingestACLs(aclDefs)
      aclDefs.nil? or aclDefs.each { |acl|
        BotCommands::ACLCreator.special(
          acl['special'],
          BotCommands::ACLCreator.mapFromYAML( acl['acl'] )
        )
      }
    end

    # Per-command ACL definitions
    def ingestCMDACLs(cmdACLs)
      cmdACLs.nil? or cmdACLs.each { |cmdACL|
        # print "cmdACL: #{cmdACL.inspect}\n"
        BotCommands::CommandList.allowACL(
          cmdACL['cmd'],
          BotCommands::ACLCreator.mapFromYAML( cmdACL['allow'] )
        )
      }
    end

    # Per-command ACL definitions
    def joinMUCs(mucs)
      mucs.nil? or mucs.each { |muc|
        jid = Jabber::JID.new( muc['jid'] )
        @msg_handler.connectMUC( jid )
        muc_session = @msg_handler.getSession( jid )
        muc['cmds'].nil? or muc['cmds'].each { |cmd|
          if cmd['run']
            print "running #{cmd['run'].inspect} in #{jid}\n"
            muc_session.handle(cmd['run'])
          end
        }
      }
    end

    def includeSubConf(ymlIncludes, depth=0)
      depth < 28 or raise ConfigParseException, "Depth too great"
      # Find other files to include/include them
      begin
        if ! ymlIncludes.nil?
          ymlIncludes.each { |inc|
            if inc.has_key?('path')
              paths = [ inc['path'] ]
            else
              paths = Dir.glob( inc['glob'] )
            end
            paths.each { |f|
              yml = YAML.load_file( f )
              ingestACLs(yml['acls'])
              ingestCMDACLs(yml['cmds'])
              joinMUCs(yml['join_mucs'])
              includeSubConf(yml['include'], depth + 1)
            }
          }
        end
      rescue ConfigParseException => e
        raise ConfigParseException, "#{e}\n in #{ymlIncludes.inspect}"
      rescue Exception => e
        raise ConfigParseException, "(#{e} :: #{e.backtrace})\n    in #{ymlIncludes.inspect}\n"
      end
    end

  end
end

