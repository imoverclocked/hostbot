#
# pastor-muppet (muppet bot) commands
#

require 'tempfile'

module BotCommands

 class GetCommand < Command
    self.command_name = 'get'
    self.acl = BotCommands.admin_acl && BotCommands.private_acl
    self.short_desc = 'downloads urls to a specified destination directory'
    self.help_text = <<EOD
get source_uri [ source_uri ... ] destination

Downloads files from an http URI into a specified destination. The destination must be
a directory and the file saved will be the same as the basename of each source_uri.
No output will be returned in the event that everything succeeds appropriately.
EOD
    self.handlePrivately = false
    CommandList.addCommandClass( GetCommand )

    def run(text)
      text["get"] = ""
      args = text.split
      destination = args.pop
      # Fix annoying iChat strings
      args.reject! { |url| url.match(/^\[.*\]$/) }
      if ! File.directory?( destination )
        say("ignoring get command: destination is not a directory")
        return
      end
      # say("getting file[s] (#{args.join(" ")}) and placing them into #{destination}.")

      # TODO: catch errors and retry/report as needed
      get_thread = args.map { |url| Thread.new {
        filename = File.basename( url )
        url = URI.parse(url)
        file = File.new("#{destination}/#{filename}", File::CREAT|File::TRUNC|File::RDWR, 0644)
        http = Net::HTTP.start(url.host, url.port) do |http|
          http.get(url.path) { |block| file.write(block) }
        end
        file.close()
      }}

      # Wait for get requests to finish
      get_thread.each { |thread| thread.join }
    end
  end

  class HostsCommand < Command
    self.command_name = 'hosts'
    self.acl = BotCommands.any_acl
    self.short_desc = 'respond with " " or my hostname'
    self.help_text = 'hosts [--name] - respond with "my" hostname'
    self.handlePrivately = false
    CommandList.addCommandClass( HostsCommand )

    def run(text)
      if text =~ /--name/
        say("#{@session.client.jid.resource}")
      else
        say(" ")
      end
    end
  end

  class InfoCommand < Command
    self.command_name = 'info'
    self.acl = BotCommands.admin_acl & BotCommands.private_acl
    self.short_desc = 'grab a bunch of information about a system in just a few quick keystrokes'
    self.help_text = 'info attempts to give information about puppet as well as output from uname -a, ifconfig -a, w'
    CommandList.addCommandClass( InfoCommand )

    def run(text)
      say("System Information:")
      PGrepCommand.new( acl_criteria(), session() ).exec(text)
      say("uname -a:\n" + `uname -a`)
      say("ifconfig -a:\n" + `ifconfig -a`)
      say("w:\n" + `w`)
    end
  end

  class PGrepCommand < Command
    self.command_name = 'pgrep'
    self.acl = BotCommands.admin_acl
    self.short_desc = 'short for process grep, a way to look for specific processes'
    self.help_text = 'pgrep filter - short for process grep, a way to look for specific processes

filter is anything that grep (platform specific!) accepts as a filter.

NB: the underlaying command looks something like: ps -ef | grep $filter | grep -v grep
'
    CommandList.addCommandClass( PGrepCommand )

    def initialize( *args )
      super( *args )
      @opts = {}
    end

    def run(text)
      filter = text.split[1]
      # Why can't all ps just get along?!?
      if ! @opts[:ps]
        `ps -ef`
        if $? == 0
          @opts[:ps] = '-ef'
        else
          @opts[:ps] = '-eax'
        end
      end
      prefix = "pgrep '#{filter}:\n"
      command = "ps #{@opts[:ps]} | grep -i '#{filter}' | grep -v grep"
      output = `#{command}`
      if output.length > 0
        say("#{prefix}: #{output}")
      end
    end
  end

  class RunCommand < Command
    self.command_name = 'run'
    self.acl = BotCommands.admin_acl && BotCommands.private_acl
    self.short_desc = 'spawns a new thread which waits for output'
    self.help_text = <<EOD
run command - spawns a new thread which waits for output from [command]

This does not work for interactive commands and there is no way (yet) to nicely
kill off the process once it is started. Running things like "run ping 127.0.0.1"
under Linux will never return. Instead you can "run ping -c 2 127.0.0.1"

Also, pipes and standard redirects should work:

"run hostname | grep local > /dev/null; echo $?"
EOD
    self.handlePrivately = false
    CommandList.addCommandClass( RunCommand )

    def run(text)
      command = text
      command["run"] = ""
      output = `#{command}`
      output = output.chomp()
      if output.length > 0
        say("Output from#{command}:\n#{output}")
      end
    end
  end

  class WatchCommand < Command
    self.command_name = 'watch'
    self.acl = BotCommands.admin_acl
    self.short_desc = 'spawns a new thread which repeatedly runs a command, waiting for a change in output'
    self.help_text = <<EOD
watch command - spawns a new thread which executes a command repeatedly waiting for differences
EOD
    # self.handlePrivately = false
    CommandList.addCommandClass( WatchCommand )

    def runIntoTmp(command)
      tmp = Tempfile.new('watch')
      tmp.write( `#{command}` )
      path = tmp.path()
      tmp.close()
      return path
    end

    def run(text)
      command = text
      command[self.class.command_name] = ""

      file0 = runIntoTmp( command )

      while ! finish?()
        file1 = runIntoTmp( command )
        differences = `diff #{file0} #{file1}`
        if $? != 0
          say( differences )
        end
        begin
          File.unlink( file0 )
        rescue Exception=>e
        end
        file0 = file1
        sleep( 1 )
      end
      say("#{text} -- has finished")
    end
  end

  class WhereisCommand < Command
    self.command_name = 'whereis'
    self.acl = BotCommands.admin_acl
    self.short_desc = 'looks through a list of resources to find matching values'
    self.help_text = <<EOD
whereis <string> -- looks through a list of resources on each host in order to find a
matching string. Some resources include mounts/logged in users/DomU/Zones/IP/MAC Adrress
and potentially many more
EOD
    self.handlePrivately = false
    CommandList.addCommandClass( WhereisCommand )

    def users(resource)
      who_list = `who`.split("\n")
      return if $? != 0
      users = who_list.map { |line| line.split.shift }
      if users.include?(resource)
        say( "user #{resource} is logged in" )
      end
    end

    def mounts(resource)
      mount_list = `mount`.split("\n")
      return if $? != 0
      mounts = mount_list.map { |line| line.split.shift }
      mounts.delete_if { |mount| mount !~ /#{resource}/ }
      if ! mounts.empty?
        mount_say = "mounted filesystems #{mounts.join(" ")}"
        say( mount_say )
      end
    end

    def xen_domains(resource)
      domain_list = `xm list`.split("\n")
      return if $? != 0
      domain_list.shift # Get rid of header
      domains = domain_list.map { |line| line.split.shift }
      domains.delete_if{ |domain| domain !~ /#{resource}/ }
      if ! domains.empty?
        domain_say = "DomU's include #{domains.join("\n")}"
        say( domain_say )
      end
    end

    def solaris_zones(resource)
      zones = `zoneadm list`.split("\n")
      return if $? != 0
      zones.delete_if{ |zone| zone !~ /#{resource}/ }
      if ! zones.empty?
        zone_say = "Zones include #{zones.join("\n")}"
        say( zone_say )
      end
    end

    def networking(resource)
      network_info = `ifconfig -a`
      if network_info =~ /#{resource}/
        say( "network stack matches given resource" )
      end
    end

    def hostname(resource)
      if @session.client.jid.resource =~ /#{resource}/
        say("I am #{@session.client.jid.resource}")
      end
    end

    def run(text)
      resource = text.split
      resource.shift # Get rid of command
      resource = resource.join(" ")
      # Look for each kind of resource.
      users( resource )
      mounts( resource )
      xen_domains( resource )
      solaris_zones( resource )
      networking( resource )
      hostname( resource )
    end
  end

  class WOMPCommand < Command
    self.command_name = 'womp'
    self.acl = BotCommands.admin_acl
    self.short_desc = 'Sends a Wake On Magic Packet to a specified MAC Address'
    self.help_text = <<EOD
womp <mac address> - send a WOMP to the specified mac address

<mac address> should be in a colon separated format
EOD
    # self.handlePrivately = false
    CommandList.addCommandClass( WOMPCommand )

    def run(text)
      addys = text.split(" ")
      addys.shift # Don't care about command name
      # Open a common UDP socket for all operations
      socket = UDPSocket.open()
      socket.setsockopt(Socket::SOL_SOCKET,Socket::SO_BROADCAST,1)
      # run all mac_addresses at once
      threads = addys.map do |mac_address|
        Thread.new do
          mac_address = mac_address.split(":").pack("H*H*H*H*H*H*")
          3.times {
            socket.send(0xff.chr * 6 + mac_address * 16, 0, '<broadcast>', "discard")
	    sleep(1)
          }
        end
      end
      # Wait for all threads to return
      threads.each do |thread|
        thread.join
      end
      # get rid of UDP socket
      socket.close()
    end
  end

end

require 'configbot/check_command'
