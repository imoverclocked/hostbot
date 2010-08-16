#
# Check related command "stuff"
#

module BotCommands

  class CheckCommand < Command
    self.command_name = 'check'
    self.acl = BotCommands.admin_acl
    self.short_desc = 'run checks for the local system'
    self.help_text = 'check [-f] [check_name] - run a check or all checks for the local system

if -f is specified, run a fix for failing checks

if no check_name is specified, run all checks available for local system
'
    self.handlePrivately = false
    CommandList.addCommandClass( CheckCommand )

    def initialize( *args )
      super( *args )
      @opts = {}
    end

    def run(text)
      # Parse words and options
      words = text.split
      options = { :fix => false }
      words.reject! { |word|
        case word
          when 'check'
            true
          when '-f'
            options[:fix] = true
            true
        end
      }

      # Run all tests if the parameter is an empty string
      if words.length == 0
        words.push("")
      end

      # Get all status messages into an array
      status = words.map { |check|
        check_status( check, options )
      }

      # ignore blank outputs
      status.reject! { |output|
        output == nil or output == false or output.length == 0
      }

      if (status.length != 0)
        say (status.join("\n"))
      end
    end

    def puppet_last_run()
      puppetfile = "/var/tmp/puppet_is_running"
      if (!File.exist?(puppetfile))
        return "Puppet has never run on this system"
      elsif ((Time.now - File.mtime(puppetfile)) < 60*60*24)
        return true
      end
      return "Puppet has not been run in the last 24 hours.  Puppet last run " + File.mtime(puppetfile).to_s
    end

    def prefixmaster?()
      return File.exist?("/etc/prefix_master")
    end

    def pksync?()
      return File.exists?("/usr/sbin/pksync")
    end

    def show_pgrep_output(text, newThread=true, returnResults=false)
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
      if newThread && !returnResults
        Thread.new { say("#{prefix}" + `#{command}`) }
      elsif returnResults
        return  `#{command}`
      else
        say("#{prefix}" + `#{command}`)
      end
    end

    def check_status(check, options = {:fix => false})
      status_string = ""
      if options[ :checksDir ] == nil
        options[ :checksDir ] = "/etc/configbot/check/"
      end

      if check.length > 0
        options[:check] = check
      else
        options[:check] = ""
      end

      if check.length == 0 or check == 'puppet'
        puppet_output = show_pgrep_output("pgrep puppetd", false, true)
        if (puppet_last_run() != true)
          status_string += "\n" + puppet_last_run()
        end
        if (puppet_output == "")
          status_string += "\nPuppet not currently running"
        end
      end

      # Quick hack to ensure one line ending exists
      status_string = status_string.chomp() + "\n"
      status_string += check_status_recurse( options ).join("\n")

      if (status_string.length < 2)
        return false
      end
      # return "Status for #{@session.client.jid.resource}:" + status_string
      return status_string
    end

    def check_status_recurse(options)
      status = []

      # Running a specific set of tests?
      if options[:check] != '' and File.directory?("#{options[:checksDir]}#{options[:check]}")
        options[:check] = ""
        options[:checksDir] = "#{options[:checksDir]}#{options[:check]}/"
        return check_status_recurse(options)
      end

      # run all checks inside of checksDir
      tests = Dir.glob("#{options[:checksDir]}*.t").sort
      fixes = Dir.glob("#{options[:checksDir]}*.f").sort
      directories = Dir.glob("#{options[:checksDir]}*").sort

      tests.reject! { |filename| ! File.file?(filename) }
      fixes.reject! { |filename| ! File.file?(filename) }
      directories.reject! { |filename| ! File.directory?(filename) }

      status = []
      # Run all tests in this directory
      # say("Tests: #{options[:checksDir]}: #{tests.join(" :: ")}")
      tests.map { |testFN|
        output = `#{testFN}`.chomp()
        if $? != 0
          if options[:fix]
            fixFN = testFN
            fixFN[".t"] = ".f"
            if fixes.index( fixFN )
              output = `#{fixFN}`.chomp()
              if output.length > 2
                status.push( "#{File.basename(fixFN)} returned: #{output}" )
              end
            else
              status.push( "no fix for #{File.basename(fixFN)}" )
            end
          else
            status.push( "#{File.basename(testFN)} returned: #{output}" )
          end
        end
      }

      # traverse directories and run tests...
      directories.map { |dir|
        options[ :checksDir ] = "#{dir}/"
        status.push( check_status_recurse(options) )
      }

      return status

    end

  end

  class PBuildCommand < CheckCommand
    self.command_name = 'pbuild'
    self.acl = BotCommands.admin_acl
    self.short_desc = 'Starts up pbuild version of clubot on prefix_masters'
    self.help_text = 'pbuild - Starts up pbuild version of clubot on prefix_masters'
    CommandList.addCommandClass( PBuildCommand )

    def run(text)
      if (prefixmaster?)
        clu_exists = File.exists?("/opt/prefix/usr/bin/clubot")
        pbuild_config = File.exists?("/etc/prefix-build-bot.xml")
        if (clu_exists and pbuild_config)
          `su tims -c "/opt/prefix/usr/bin/clubot -c /etc/prefix-build-bot.xml &"`
        else
           # err = "#{@client.jid.resource}: is a prefix_master but an error has occured\n";
           err = "I am a prefix_master but an error has occured\n";
           if (!clu_exists)
              err << "/opt/prefix/usr/bin/clubot doesn't exist on the system\n"
           end
           if (!pbuild_config)
              err << "/etc/prefix-build-bot.xml doesn't exist on the system"
           end
           say (err)
        end
      end
    end
  end

  class PrefixCommand < CheckCommand
    self.command_name = 'prefix'
    self.acl = BotCommands.admin_acl
    self.short_desc = 'does something with prefix ... not sure what yet'
    self.help_text = 'prefix - does something with prefix ... not sure what yet'
    CommandList.addCommandClass( PrefixCommand )

    def run(text)
      if (!pksync?())
        say("pksync not installed yet")
      else
        say("TODO STUB for prefix command")
      end
    end
  end

end
