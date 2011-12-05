#
# Check related command "stuff"
#

module BotCommands

  class CheckCommand < Command
    self.command_name = 'check'
    self.acl = BotCommands.admin_acl && BotCommands.private_acl
    self.short_desc = 'run checks for the local system'
    self.help_text = 'check [-f] [check_name] - run a check or all checks for the local system

if -l is specified lists all current checks

if -f is specified, run a fix for failing checks

if no check_name is specified, run all checks available for local system
'
    self.handlePrivately = false
    CommandList.addCommandClass( CheckCommand )

    def initialize( *args )
      super( *args )
      @opts = {:slcheck=> true, :fix => false, :list => false, :checksDir=>"/etc/configbot/check/"}
    end

    def reject(words)
      words.reject! {|word|
        case word
          when 'check'
            true
          when '--nosl'
            @opts[:slcheck] = false
            true
          when '-f'
            @opts[:fix] = true
            true
          when '-l'
            @opts[:list] = true
            true
        end
      }
      return words
    end

    def run(text)
      # Parse words and options
      words = text.split
      if @opts[ :checksDir ] == nil
        @opts[ :checksDir ] = "/etc/configbot/check/"
      end
      words = reject(words)
      options =@opts
      if (options[:list] == true)
        if words.length == 0
          tests = Dir.glob("#{options[:checksDir]}/**/*.t")
          tests.map!{ |t| dir_array = t.split(".")[0].split("/"); test = dir_array.pop; "#{dir_array.pop}/#{test}" }
          say (tests.chomp.join(", "))
        else
          words.each{ |check| 
            tests = Dir.glob("#{options[:checksDir]}/#{check}/*.t")
            tests.map!{ |t| dir_array = t.split(".")[0].split("/"); test = dir_array.pop; "#{dir_array.pop}/#{test}" }
            say (tests.chomp.join(", "))
          }
        end
     else
      # Run all tests if the parameter is an empty string
      if words.length == 0
        words.push("")
      end

      # Get all status messages into an array
      status = []
      #status = words.map { |check|
      #  check_status(check,options )
      #}
		words.each{ |check|
		  status += check_status(check, options)
		}
      # ignore blank outputs
      status.map!{ |output| 
        if (output.class == String) 
          output.strip
        else
          output
        end 
      }
      status.reject! { |output|
        output == nil or output == false or output.length == 0
      }
      status.each { |stat| 
            if (stat.length != 0 )
               say("#{stat.chomp}\n") 
            end      
      }
    end
      if (options[:slcheck])
        @opts[:checksDir] = "/etc/configbot/slcheck/"
        @opts[:slcheck] = false
        sltext = text
        sltext.slice!("--nosl")
        self.run(sltext)
      end
    end

    def prefixmaster?()
      return File.exist?("/etc/prefix_master")
    end

    def pksync?()
      return File.exists?("/usr/sbin/pksync")
    end

    def check_status(check, options = {:fix => false})
      if options[ :checksDir ] == nil
        options[ :checksDir ] = "/etc/configbot/check/"
      end

      if check.length > 0
        options[:check] = check
      else
        options[:check] = ""
      end
	return check_status_recurse(options)
    end

    def check_status_recurse(options)
      status = []
      # Running a specific set of tests?
      if options[:check] != '' and File.directory?("#{options[:checksDir]}#{options[:check]}")
        options[:checksDir] = "#{options[:checksDir]}#{options[:check]}/"
        options[:check] = ""
        return check_status_recurse(options)
      elsif options[:check] != ''
        return []
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
        output = `#{testFN}`.strip
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
          elsif output.length > 0
              status.push( "#{File.dirname(testFN).split("/").pop}/#{File.basename(testFN)} returned: #{output}" )
          end
        end
      }

      # traverse directories and run tests...
      directories.map { |dir|
        options[ :checksDir ] = "#{dir}/"
        status += check_status_recurse(options) 
      }
      return status

    end

  end

  class SLCheckCommand < CheckCommand
    self.command_name = 'slcheck'
    self.acl = BotCommands.admin_acl && BotCommands.private_acl
    self.short_desc = 'Run system wide checks'
    self.help_text = 'Run system wide checks'
    self.handlePrivately = false
    CommandList.addCommandClass(SLCheckCommand)

    def initialize( *args )
      super(*args)
      @opts[:checksDir] ="/etc/configbot/slcheck/"
      @opts[:slcheck] = false
    end
    def reject(words)
      words.reject! {|word|
        case word
          when 'slcheck'
            true
          when '-l'
            @opts[:list] = true
            true
        end
      }
      return words
    end
  end 

  class PBuildCommand < CheckCommand
    self.command_name = 'pbuild'
    self.acl = BotCommands.admin_acl && BotCommands.private_acl
    self.short_desc = 'Starts up pbuild version of clubot on prefix_masters'
    self.help_text = 'pbuild - Starts up pbuild version of clubot on prefix_masters'
    CommandList.addCommandClass( PBuildCommand )

    def run(text)
      if (prefixmaster?)
        clu_exists = File.exists?("/opt/prefix/usr/bin/clubot")
        pbuild_config = File.exists?("/etc/prefix-build-bot.xml")
        if (clu_exists and pbuild_config)
          `su prefix -c "/opt/prefix/usr/bin/clubot -c /etc/prefix-build-bot.xml &"`
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
    self.acl = BotCommands.admin_acl && BotCommands.private_acl
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
