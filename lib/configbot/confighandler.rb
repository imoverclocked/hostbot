# Configuration handler for HiRISE/PIRL hosts

# Neede for the "get" command
require 'net/http'
require 'net/https'
require 'uri'

require 'configbot/basehandler'
require 'configbot/commands'

module HiBot

  ##############################################################################
  # Response Handlers for commands
  ##############################################################################
  class CommandResponseHandler < ResponseHandler

    def handle(text)
      keyword = text.split.shift
      commands = BotCommands::CommandList.commandsByName

      action = commands[ keyword ]
      if action != nil
        command = action.new( acl_criteria(), @sess )
        return command.exec(text)
      end
      unrecognizedResponse( text )
    end

    def incomingFile( iq, file, file_helper )
      fileTransfer = BotCommands::CommandList.incomingFile.new( acl_criteria(), @sess )
      fileTransfer.exec( iq, file, file_helper )
      # hack!
      return true
    end

    def cleanup(text)
      @client.cleanup(text)
    end

    def show_help(text)
      topic = text.split
      if topic.length <= 1
        commands = @responses.keys.sort.join(", ")
        say("available commands: #{commands}")
      else
        if @contextual_help[topic[1]]
          say("#{@contextual_help[topic[1]]}")
        else
          say("contextual help not yet available for #{topic[1]}")
        end
      end
    end

    # When we don't know what to say, say this
    def unrecognizedResponse( text )
      print "Unrecognized Response: #{text}"
    end
  end

  class MUCResponseHandler < CommandResponseHandler
    def init_acl_criteria( acl_criteria )
      super( acl_criteria )
    end

    def joinedRoom( nick )
    end

    def leftRoom( nick )
    end

    # Returns true if a message should be handled privately (WRT MUC)
    #   -- if we return "yes" then this instance doesn't handle(text)
    #   The MUCSession uses this
    def handlePrivately?(text)
      keyword = text.split.shift
      commands = BotCommands::CommandList.commandsByName
      action = commands[ keyword ]
      if action
        return action.handlePrivately?(text)
      end
    end

    def roomCan?(text, nick)
      keyword = text.split.shift
      commands = BotCommands::CommandList.commandsByName
      action = commands[ keyword ]
      if ! action
        return false
      end

      acl_criteria = @acl_criteria
      acl_criteria[ :user_role ] = @sess.muc.role( nick )
      return action.new( acl_criteria, @sess ).can?( acl_criteria )
    end

    # When we don't know what to say, don't say anything
    def unrecognizedResponse( text )
      # This is evil, don't ever respond ... makes a bad infinite loop
      # between bots that are talking to each other. They keep telling
      # each other "Command not found..." which prompts a
      # "Command not found" response
      ## say ("Command not found.  Did you forget 'run'?")
      p "Unrecognized Response: #{text}"
    end
  end

end
