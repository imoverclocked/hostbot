#... groups implementation for @alias and @module:kv_pairs
#
#  We have two ways of using the @symbol:
#    @alias
#    @module:kv_pairs
#
#    the alias method uses defined alises in the BotCommands::Groups::@aliases
#    has to resolve to a @module:kv_pairs definition
#
#      eg: @Darwin => @Puppet:kernel=Darwin
#      eg: @SnowLeopard => @Puppet:kernel=Darwin,macosx_productversion_major=10.6
#      and maybe someday:
#        eg: @virtual => @Puppet:virtual=vserver || virtual=xenu || virtual=zone
#
#    the module:kv_pairs is defined as:
#      module  : the name of a module to identify a pool of computers based on kv_pairs
#      kv_pairs: an operator separated list of k=v
#
#      eg: @Puppet:kernel=Darwin
#
#    an alias might be: @Darwin => @Puppet:kernel=Darwin

module BotCommands

  # Static class

  class Groups
    @@aliases = {}        # Hash of alias => module:kv_pairs
    @@sticky = []
    # accessor methods
    def self.aliases; @@aliases; end
    def self.sticky; @@sticky; end

    class << self
      # replaces previously known commands with later defined commands
      def addAlias( aliasName, kv_pairs, sticky=true )
        # TODO: make sure this is a valid kv_pairs and fail early
        #
        aliasName.downcase!
        if aliasName[0] == ?@ and !@@sticky.include?(aliasName)
          @@aliases[ aliasName ] = kv_pairs
          if sticky
            @@sticky.push(aliasName)
          end
        end
      end
      def remAlias(aliasName)
        if @@aliases[aliasName] and !@@sticky.include?(aliasName)
          @@aliases.delete(aliasName)
          return true
        end
        return false
      end

      # takes a @keyword/@module:kv_pairs and returns a list of nodes
      def resolve( muc_session, keyword_alias )
        if ! @@aliases[ keyword_alias ]
          if keyword_alias[0] == ?/ 
            return resolve_module( muc_session, "@Regex:regex=#{keyword_alias}" )
          elsif keyword_alias[0] == ?@ and keyword_alias[1] ==?/
            keyword_alias.slice!(0)
            return resolve_module( muc_session, "@Regex:regex=#{keyword_alias}" )
          elsif !keyword_alias.match(/^\@/)
            return  keyword_alias
          end
          return resolve_module( muc_session, keyword_alias )
        end
        return resolve_alias(muc_session, keyword_alias )
      end

      # takes a @keyword returns a list of nodes
      def resolve_alias( muc_session, keyword_alias )
       return resolve( muc_session, @@aliases[ keyword_alias ] )
      end

      # takes a @module:kv_pairs and returns a list of nodes
      def resolve_module( muc_session, keyword_alias )
        # Find module name/kv_pairs
        ## instantiate {moduleName}Module (eg: PuppetModule)
        ## get list of nodes from modules
        ## node_gen = PuppetModule.new( muc_session, kv_pairs )
        ## node_gen.resolve_module()
        keyword_array = keyword_alias.split(":", 2)
        module_str = keyword_array[0]
        kv_pairs= keyword_array[1]
        module_str.downcase!
        case module_str
          when "@Puppet", "@puppet"
            node_gen=PuppetModule.new(muc_session, kv_pairs)
          when  "@Regex", "@regex"
            node_gen=RegexModule.new(muc_session, kv_pairs)
          when "@in_room", "@InRoom", "@In_Room"
            node_gen=RoomModule.new(muc_session, kv_pairs)
          when "@missing", "@Missing"
            node_gen=MissingModule.new(muc_session, kv_pairs)
          when "@all_nodes", "@AllNodes", "@All_Nodes"
            node_gen=AllNodesModule.new(muc_session, kv_pairs)
          when "@List", "@list"
            node_gen=ListModule.new(muc_session, kv_pairs)
          when "@Random", "@random"
            node_gen=RandomModule.new(muc_session, kv_pairs)
          else
            print "Couldn't find correct module, error?"
            return Array.new
        end
        node_gen.resolve_module()
      end
    end
  end
  class GenericModule
    # new method
    # @kv_pairs
    # @muc_session
    def initialize (muc_session, kv_pairs)
      @kv_pairs = kv_pairs
      if @kv_pairs == nil
        @kv_pairs = String.new
      end
      @muc_session = muc_session
      dir = "/var/lib/puppet/yaml/facts/"
      all_files = Dir.new(dir).entries.sort!
      @all_nodes = Array.new
      all_files.each do |nf|
        if File.file?("#{dir}#{nf}")
          shortname = nf.split(".")[0]
          @all_nodes.push(shortname)
        end
      end
      @all_nodes.uniq!.sort!
    end
    def resolve_module()
      return Array.new
    end
  end
  class AllNodesModule < GenericModule
    def resolve_module()
      return @all_nodes
    end
  end

  class RoomModule < GenericModule
    def initialize (muc_session, kv_pairs)
      @muc_session = muc_session
      @kv_pairs = kv_pairs
      if @kv_pairs == nil
        @kv_pairs = String.new
      end
      muc_roster = @muc_session.bot_list.map!{ |nick| nick.split("/")[1] }
      @in_room = muc_roster.map { |nick| nick.downcase.split(".")[0] }
    end

    def resolve_module()
      return @in_room
    end 
  end
  class ListModule < GenericModule
    def resolve_module()
      bot_list = @kv_pairs.split(",")
      in_room = @muc_session.muc_roster.map { |nick| nick.downcase.split(".")[0] }
      all_nodes = in_room | @all_nodes
      final_list = Array.new
      bot_list.each{ |bot| 
        if (bot[0] == ?/ and bot[bot.length-1] == ?/)
          bot.slice!(0)
          bot.slice!(bot.length-1)
          final_list = final_list | all_nodes.select { |node| node =~ Regexp.new(bot) }
        else
          final_list = final_list | all_nodes.select { |node| node == bot }
        end
      }
      return final_list
    end
  end
  class RegexModule < RoomModule
    def resolve_module()
      regex = @kv_pairs.split("=", 2)[1]
      if regex != nil
        if regex.match(/^\/.*\/$/)
          regex = regex[1,regex.length-2]
        end
        ret_nodes = []
        @in_room.each do |nick|
          if nick.match( regex )
            ret_nodes.push( nick )
          end
        end
        return ret_nodes.uniq.sort!
      end
    end
  end

  class RandomModule < RoomModule
    def resolve_module()
      rand_array = Array.new
      num_rand = 1
      if (@kv_pairs.to_i > 0 and @kv_pairs.to_i <= @in_room.length)
        num_rand = @kv_pairs.to_i
      end
      while (rand_array.length < num_rand)
        rand_array.push(@in_room[rand(@in_room.length)])
        rand_array.uniq!
      end
      return rand_array
    end
  end

  class PuppetModule < GenericModule
      # implements the module named "Puppet"
      def resolve_module()
        kv_pairs = @kv_pairs
        results = @all_nodes.to_set
        kv_pairs.split(",").each do |kv|
          key_val = kv.split("=")
          cmd = "/etc/puppet/files/display_facter.rb -p #{key_val[0]} | grep #{key_val[1]}"
          tmp_results = `#{cmd}`.split(":")
          if tmp_results.length > 1
            tmp_results.pop()
            tmp_results = tmp_results.join(":").split(", ")
          else
            tmp_results=[]
          end
          results = results&(tmp_results)
        end
        return results.to_a
     end
  end

  class MissingModule < PuppetModule
    def resolve_module()
      node_gen=RoomModule.new(@muc_session, @kv_pairs) 
      return @all_nodes - node_gen.resolve_module()
    end
  end

end


