#
# pastor-muppet (muppet bot) commands
#
BotCommands::Groups.addAlias("@Darwin", "@Puppet:kernel=Darwin")
BotCommands::Groups.addAlias("@SunOS", "@Puppet:kernel=SunOS")
BotCommands::Groups.addAlias("@Linux", "@Puppet:kernel=Linux")
BotCommands::Groups.addAlias("@Solaris", "@Puppet:operatingsystem=Solaris")
BotCommands::Groups.addAlias("@Debian", "@Puppet:operatingsystem=Debian")
BotCommands::Groups.addAlias("@SnowLeopard", "@Puppet:kernel=Darwin, macosx_productversion_major=10.6")
BotCommands::Groups.addAlias("@Leopard", "@Puppet:kernel=Darwin, macosx_productversion_major=10.5")
BotCommands::Groups.addAlias("@cnodes", "@Regex:regex=/cnode[0-9]*/")
BotCommands::Groups.addAlias("@pnodes", "@Regex:regex=/pnode[0-9]*/")
BotCommands::Groups.addAlias("@xen", "@Regex:regex=/xen-*/")
BotCommands::Groups.addAlias("@missing", "@missing:Systems that are missing from the room")
BotCommands::Groups.addAlias("@in_room", "@in_room:Systems that are in the room")
BotCommands::Groups.addAlias("@hinet", "@Puppet:network_side=hinet")
BotCommands::Groups.addAlias("@pirlnet", "@Puppet:network_side=pirlnet")


module BotCommands

  def self.allowInternalMuppet; @@allowInternalMuppet_acl; end
  @@allowInternalMuppet_acl = ACLMatchAny.new( ACLItem.new(:or, :bot_type, :muppetbot) )

  class AddBotCommand < Command
    self.command_name = 'addBot'
    self.acl = BotCommands.allowInternalMuppet
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
    self.acl = BotCommands.allowInternalMuppet
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

  class UnaliasCommand < Command
    self.command_name = 'unalias'
    self.acl = BotCommands.allowInternalMuppet
    self.handlePrivately = false
    self.short_desc = "Remove non permanent aliases from skynet"
    self.help_text = "Remove non permanent aliases from skynet"
    CommandList.addCommandClass( UnaliasCommand)
    def run(text)
      command = text.split
      command.shift
      if command.length == 0
        say("Usage:  unalias [alias]")
      else
        if (BotCommands::Groups.remAlias(command[0]))
          say("Alias #{command[0]} successfully removed")
        else
          say("Alias #{command[0]} could not be removed")
        end
      end
    end
  end
  class AliasCommand < Command
    self.command_name = 'alias'
    self.acl = BotCommands.allowInternalMuppet
    self.handlePrivately = false
    self.short_desc = "Define or display aliases for skynet"
    self.help_text = "Define or display aliases for skynet:
alias [alias-name[=string]
alias               # list all defined aliases
alias @alias        # list @alias definition if it exists
alias @alias=string # set @alias to = string (if it's valid and if @alias isn't predefined and permanent)
Ex: alias @example=@List:complicated,guru   # Sets the alias @example to the nodes guru and complicated 
further examples can be gleaned from running alias without arguments"
    CommandList.addCommandClass( AliasCommand)
    def run(text)
      command = text.split
      command.shift
      if (command.length == 0)
        BotCommands::Groups.aliases.each {|key, value|
          say("#{key}: #{value}")
        }
      else
        aliases=command[0].split("=",2)
        if aliases[0][0] != ?@
          say("Aliases must begin with @ symbol.")
          return
        end
        if aliases.length==1
          if BotCommands::Groups.aliases.include?(aliases[0].downcase)
            say("Alias: #{aliases[0]} = " + "#{BotCommands::Groups.aliases[aliases[0].downcase]}")
          else
            say("Alias: #{aliases[0]} doesn't exist")
          end
        else
          if BotCommands::Groups.sticky.include?(aliases[0].downcase)
            say("Alias: #{aliases[0]} already exists and is permanent")
          else
            nodes = Groups.resolve(@session, aliases[1])
            if (nodes.kind_of?(Array))
              BotCommands::Groups.addAlias(aliases[0], aliases[1], false)
              nodes = Groups.resolve(@session, aliases[0]) 
              short_nodes = HiBot::AggregatorHelpers.node_shorthand_ranges( nodes )
              say("(#{aliases[0]}): #{short_nodes}")
            else 
              say("Alias: #{aliases[0]}=#{aliases[1]} failed, so not added")
            end
          end
        end
      end
    end
  end

  class NodesCommand < Command
    self.command_name = 'nodes'
    self.acl = BotCommands.allowInternalMuppet
    self.handlePrivately = false
    self.short_desc = "show all/groups of nodes"
    self.help_text = "Lists nodes that are known to the bot.
nodes               # list nodes in the room
nodes @in_room      # list nodes in the room
nodes @missing      # list missing nodes
nodes /cnode[0-9]*/ # list all nodes in the room matching the regex
nodes @alias        # list nodes matching the alias

@missing generation:
Using the data stored by facter and the room roster of the MUC displays nodes which have registered with muppet but aren't currently in the room"
    CommandList.addCommandClass(NodesCommand)
    def run (text)
      command = text.split
      command.shift
      nodes = []

      if command.length == 0
        command_desc = "@in_room"
      else
        command_desc = command.join(" ")
      end
      nodes = Groups.resolve(@session, command_desc) 
      short_nodes = HiBot::AggregatorHelpers.node_shorthand_ranges( nodes )
      say("(#{command_desc}): #{short_nodes}")
    end
  end

  class PuppetCommand < Command
    self.command_name = 'puppet'
    self.acl = BotCommands.allowInternalMuppet
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
    self.acl = BotCommands.allowInternalMuppet
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
               if val[1].kind_of? Time
                 val[1] = val[1].to_s
               end 
               if val[1].kind_of? String
                 if /#{whereis}/.match(val[1])
                    if (display[y[0]]) == nil
                       display[y[0]] = Array.new
                    end
                    display[y[0]].push("#{val[0]}: #{val[1]}")
                 end
               end
            end
         end
      end
      display.sort.each do |y,z|
         say("Found in #{y} puppet info: #{z.join(", ")}\nFor more information type in chatroom: ask -n #{y}")
      end
    end
  end
  class PuppetCACommand < Command
    self.command_name = 'puppetca'
         self.acl = BotCommands.allowInternalMuppet
         self.short_desc = "Interaction with puppet certificate authority."
         self.help_text = "Interaction with puppet certificate authority."
         CommandList.addCommandClass(PuppetCACommand)
         def run (text)
	   command = "puppet cert " + text.split(' ')[1..-1].join(' ')
           say(`#{command}`)  
         end
  end
  class RetireCommand < Command
    self.command_name = 'retire'
    self.acl = BotCommands.allowInternalMuppet
    self.short_desc = "Retire systems no longer in use"
    self.help_text = "USAGE:  retire [name] -- To retire a system\nretire -u [name] --To unretire a system"
    CommandList.addCommandClass(RetireCommand)
    def run (text)
        dir = "/var/lib/puppet/yaml/facts/"
            args = text.split
            args.shift
        if (args[0] and args[0].length > 0 and args[0][0,1] != "." and args[0][0,1] != "/" and args[0] != "-u")
           `mv #{dir}#{args[0]}* #{dir}/retired`
					  `if which puppetca &> /dev/null; then puppetca --list --all | grep ^+ | grep #{args[0]} | awk '{print $2}' | while read LINE; do puppetca --clean $LINE; done fi`
        elsif (args[1].length > 0 and args[0] == "-u" and args[1][0,1] != "." and args[1][0,1] != "/")
           `mv #{dir}/retired/#{args[1]}* #{dir}`
        else
           say("USAGE:  retire [name] -- To retire a system")
           say("retire -u [name] --To unretire a system")
        end
    end
  end

  class MissingCommand < Command
    self.command_name = 'missing'
    self.handlePrivately = false
    self.acl = BotCommands.allowInternalMuppet
    self.short_desc = "Displays missing nodes! -- deprecated"
    self.help_text = "see the 'nodes' command for extended usage:
nodes @missing"
    CommandList.addCommandClass(MissingCommand)
    def run (text)
        say("'missing' is deprecated in favor of 'nodes @missing'")
    end
  end

  class SkynetCommand < Command
    @@command_id = 0
    @group = nil
    @@skynet_maps = { 'womp' => :womp, 'check' => :check }
    self.command_name = 'skynet'
    self.handlePrivately = false
    self.acl = BotCommands.allowInternalMuppet
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
          resolved = Groups.resolve(@session, addy) 
          if (resolved.kind_of?(Array))
            say ("Womping: #{resolved.join(", ")}")
		        resolved.each do |node|
		          mac_from_puppet(node).each do|mac|
		    	      mac_addys.push(mac)
		    	    end
		        end
          else
            mac_addys.push(mac_from_puppet(resolved))
          end
        end
      end
      if mac_addys.length < 1
        say( "Could not resolve any arguments into MAC addresses" )
        return ""
      end
      return "womp #{mac_addys.join(" ")}"
    end

    def check(text)
      group = @group
      num_rand = 5
      if group == nil
        group = "@in_room"
      end
      formatted_bots = @session.bot_list.map { |node| node.split("/").pop.downcase }
      group_bots = Groups.resolve(@session, group)
      in_room = Set.new(group_bots) & Set.new(formatted_bots)
      in_room = in_room.to_a
      rand_array = Array.new
      #discover = Jabber::Discovery::Helper.new(@session.client)
      while (rand_array.length < num_rand and in_room.length > 0)
        jid = in_room[rand(in_room.length)]
        features = @session.get_features_for("hostbot@bots.uahirise.org/#{jid}")
        if features.include?("http://uahirise.org/configbot/slcheck/")
          rand_array.push(jid)
        end
        in_room.delete(jid)
      end
      args = text.split
      args.shift
      args = args.join
      self.run("skynet @List:#{rand_array.join(",")} slcheck #{args}")
      text = text + " --nosl"
      return text
    end

    def mac_from_puppet( address )
      yaml_info = `/etc/puppet/files/display_facter.rb -n #{address} | grep macaddress | awk '{print $3}'`
      ret = yaml_info.split
      ret.uniq!
      return ret
    end

    def run (text)
      command = text.split(" ")
      command.shift
      nodes =""
      group = command[0]
      if group[0] == ?@
        nodes = Groups.resolve(@session, group)
        if nodes.kind_of?(Array)
          @group = group
          command.delete(group)
        end
      end
	    bot_list = @session.bot_list
      not_sent = Array.new
  		if (nodes.kind_of?(Array))
        formatted_bots = bot_list.map { |node| node.split("/").pop.downcase }
        not_sent = nodes - formatted_bots
	      bot_list.delete_if{|x| !nodes.include?(x.split("/").pop.downcase) }
  		end

      # Figure out what to send to the bot (map maps a command)
      remote_command = command[0]
      map_fn = @@skynet_maps[ remote_command ]
      if map_fn
        command = self.send( map_fn, command.join(" ") ).split(" ")
      end

      client = @session.client
      muc = nil
      begin
        muc = @session.muc
      rescue Exception=>e
      end
      command_id = HiBot::Aggregator.newID( "#{command[0]}", @session, msg_timeout = 5, max_delay = 15, bot_list)
      if not_sent.length != 0
        say ("Not in room, command not sent to : #{not_sent.join(", ")}")
      end
      bot_list.each { |nick|
        session = client.getSession(nick, muc)
        session.say( "id #{command_id} #{command.join(" ")}" )
      }
    end

  end

end
