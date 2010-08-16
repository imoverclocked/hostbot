#
# pastor-muppet (muppet bot) commands
#

module BotCommands

  def self.muppetadmin_acl; @@muppetadmin_acl; end
  @@muppetadmin_acl = ACLMatchAny.new(@@admin_acl)
  @@muppetadmin_acl.criteria.push(ACLItem.new(:or, :bot_type, :muppetbot))

  def self.muppetany_acl; @@muppetany_acl; end
  @@muppetany_acl = ACL.new(ACLItem.new(:or, :bot_type, :muppetbot))

  class AddBotCommand < Command
    self.command_name = 'addBot'
    self.acl = BotCommands.muppetadmin_acl
    self.handlePrivately = false
    self.short_desc = "Adds a bot to the roster"
    self.help_text = "addBot {jid} -- Adds a bot to the roster"
    CommandList.addCommandClass( AddBotCommand)
    def run(text)
      jid = text.split.pop
      Thread.new() {
        say("Adding bot: #{jid}")
        @session.client.helpers[:roster].add( jid, 'bot', true )
        say("Bot added: #{jid}")
      }
    end
  end

  class AskCommand < Command
    self.command_name = 'ask'
    self.acl = BotCommands.muppetany_acl
    self.handlePrivately = false
    self.short_desc = "Asks muppetbot for information about the various nodes that it has knowledge of"
    self.help_text = "ask the puppet master about various parameters for nodes that talk to it.
Usage:  ask -n node  e.g. ask -n terby
ask -p  parameter  e.g. ask -p operatingsystem
ask -p parameter -n node e.g. combine the two!
"
    CommandList.addCommandClass( AskCommand)
    def run(text)
      say(`/etc/puppet/files/display_facter.rb #{text}`)
    end
  end

  class PuppetCommand < Command
    self.command_name = 'puppet'
    self.acl = BotCommands.muppetadmin_acl
    self.short_desc = "A jabber interface for configuring nodes in puppet"
    self.help_text = "Modifies the node heirarchy for puppet.  
puppet -l       #list all possible definitions 
puppet -n       #list all nodes 
puppet -n node        #list all included rules assigned to node
puppet -a node definition   #add [definition] to [node]
puppet -d node defintion    #delete [definition] from [node]
"
    CommandList.addCommandClass(PuppetCommand)
    def run(text)
      say (`/etc/puppet/files/readnode.rb #{text}`)
    end
  end

  class WhereisCommand < Command
    self.command_name = 'whereis'
    self.handlePrivately = false
    self.acl = BotCommands.muppetadmin_acl
    self.short_desc = "looks through a list of puppet resources to find matching values"
    self.help_text = "looks through a list of puppet resources to find matching values"
    CommandList.addCommandClass(WhereisCommand)
    def run (text)
      require "yaml"
      whereis = text.split[1]   
      yaml_files = {}
      dir = "/var/lib/puppet/yaml/facts/"
      all_files = Dir.new(dir).entries
      display = {}
      all_files.each do |nf|
         if File.file?("#{dir}#{nf}")
            shortname = nf.split(".")[0]
            tmp_file = YAML::load_file("#{dir}#{nf}")
            if yaml_files.has_key?(shortname) #Picks the most recent file as the most accurate one in the case of .local or something similar
               o =  yaml_files[shortname].ivars['expiration']
               n =  tmp_file.ivars['expiration']
               if (DateTime.parse("#{n}") > DateTime.parse("#{o}") )
                  yaml_files[shortname] = tmp_file
               end
            else
               yaml_files[shortname] = tmp_file
            end
         end
      end
      yaml_files.each do |y|
         if (y[1] and defined? y[1].ivars)
            y[1].ivars['values'].each do |val|
               if /#{whereis}/.match(val[1])
                  if (display[y[0]]) == nil
                     display[y[0]] = Array.new
                  end
                  display[y[0]].push("#{val[0]}: #{val[1]}")
               end
            end
         end
      end
      display.sort.each do |y,z|
         say ("Found in #{y} puppet info: #{z.join(", ")}\nFor more information type in chatroom: ask -n #{y}")
      end
    end
  end

  class MissingCommand < Command
    self.command_name = 'missing'
    self.handlePrivately = false
    self.acl = BotCommands.muppetany_acl
    self.short_desc = "Displays missing nodes!"
    self.help_text = "Using the data stored by facter and the room roster of the MUC displays nodes which have registered with muppet but aren't currently in the room"
    CommandList.addCommandClass(MissingCommand)
    def run (text)
        in_room = @session.muc_roster.map { |nick| nick.downcase.split(".")[0] }
        dir = "/var/lib/puppet/yaml/facts/"
        all_files = Dir.new(dir).entries.sort!
        all_nodes = Array.new
        all_files.each do |nf|
          if File.file?("#{dir}#{nf}")
            shortname = nf.split(".")[0]
            all_nodes.push(shortname)
          end
        end
        all_nodes.uniq!
        missing = all_nodes - in_room
        missing_txt = missing.join(", ")
        say("Missing Nodes: #{missing_txt}")
    end
  end

  class SkynetCommand < Command
    @@command_id = 0
    @@skynet_maps = { 'womp' => :womp }
    self.command_name = 'skynet'
    self.handlePrivately = false
    self.acl = BotCommands.muppetadmin_acl
    self.short_desc = "Sends a command privately to all logged in nodes"
    self.help_text = "skynet [--nps=N] -- <command>
sends a command to all logged in nodes and attempts to aggregate similar outputs
from the nodes together to reduce the amount of duplicate messages that nodes
will return.

--nps=N  -- specify how many nodes per second to contact. This is useful for commands that could
            potentially cause a DOS on a particular resource from hundreds/thousands of nodes running
            a command at the same time."
    CommandList.addCommandClass(SkynetCommand)

    # Map names into MAC addresses
    def womp(text)
      addresses = text.split(" ")
      addresses.shift
      mac_addys = []
      addresses.each do |addy|
        pieces = addy.split(":")
        if pieces.length == 6
          # This looks and smells like a MAC address ...
          mac_addys.push( addy )
        else
          # Lookup MAC address for hostname...
          mac_from_puppet( addy ).each do |mac|
            mac_addys.push( mac )
          end
        end
      end
      if mac_addys.length < 1
        say( "Could not resolve any arguments into MAC addresses" )
        return ""
      end
      return "womp #{mac_addys.join(" ")}"
    end

    def mac_from_puppet( address )
      yaml_info = `/etc/puppet/files/display_facter.rb -n #{address} | grep macaddress | awk '{print $3}'`
      ret = yaml_info.split
      ret.uniq!
      # TODO: resolve the names into a list of MAC addresses
      return ret
    end

    def run (text)
      command = text.split(" ")
      command.shift
      remote_command = command[0]
      map_fn = @@skynet_maps[ remote_command ]
      if map_fn
        command = self.send( map_fn, command.join(" ") ).split(" ")
      end
      bot_list = @session.bot_list
      client = @session.client
      muc = nil
      begin
        muc = @session.muc
      rescue Exception=>e
      end
      command_id = HiBot::Aggregator.newID( "#{command[0]}", @session, msg_timeout = 1, max_delay = 3 )
      bot_list.each { |nick|
        session = client.getSession(nick, muc)
        session.say( "id #{command_id} #{command.join(" ")}" )
      }
    end

  end

end
