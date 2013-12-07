#
# service bot commands
#

module BotCommands

  def self.allowInternalService; @@allowInternalService_acl; end
  @@allowInternalService_acl = ACLMatchAny.new( ACLItem.new(:or, :bot_type, :servicebot) )

  class ServiceCommand < MetaCommand
    self.command_name = 'service'
    self.acl = BotCommands.any_acl
    self.handlePrivately = false
    self.short_desc = "interface to service watching infrastructure"
    self.help_text = "interface to service watching infrastructure"
    CommandList.addCommandClass(ServiceCommand)

    def help (text)
      say("try: help #{self.class.command_name}")
    end
  end

  class ServiceListCommand < Command
    self.command_name = 'service list'
    self.acl = BotCommands.allowInternalService
    self.handlePrivately = false
    self.short_desc = "list service watches"
    self.help_text = "list service watches"
    CommandList.addCommandClass(ServiceListCommand)
    def run (text)
      command = text.split
      cmd = command.shift
      sub_cmd = command.shift

      say("list... #{cmd}: #{sub_cmd}")
    end
  end

end
