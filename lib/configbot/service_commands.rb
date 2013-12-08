#
# service bot commands/infrastructure
#

module ServiceTests

  # Container for services. Can not be a static class since different MUCs or
  # JIDs may have different sets of tests. Also, this is not a flat list of
  # service objects since service checks follow a heirarchy. That is, some
  # checks should only be run if a superior check passes. A simple example is
  #
  #   web-proxy.svc
  #   web-proxy/backend1.svc
  #   web-proxy/backend2.svc
  #   web-proxy/backend3.svc
  #   web-proxy/backend3/application1.svc
  #   web-proxy/backend3/application2.svc
  #   web-proxy/backend3/application3.svc
  #
  # ... there is no point in running tests for services behind web-proxy if
  #     web-proxy itself is failing. Similarly, checking application status
  #     on a backend that is known to have failed makes no sense.
  # 
  # That being said, it's nice in this environment to deal programatically
  # with lists or flat data so many accessors will return flat lists.

  class ServiceContainer
    attr_accessor :base_services

    def initialize(session)
      @base_services = Array.new()
      @session = session
    end

    def addDir(dir)
      base_services << MetaService(dir)
    end

    def run()
      res = @base_services.collect { |svc| svc.run() }
      res.flatten.each { |result| @session.say(result) }
    end

    def list()
      res = @base_services.collect { |svc| svc.list() }
      res.flatten
    end
  end

  # Since we can have directories that don't have actual checks, it makes sense
  # to have "empty" services to maintain the heirarchy

  class MetaService
    attr_reader :name
    attr_reader :dir

    def initialize(dir, name=".")
      @dir  = dir
      @name = name
      @subService = Array.new()
      files = Dir.glob("#{dir}/*")
      dirs  = files.select { |d| File.directory?(d) }
      tests = files.select { |f| f =~ /\.svc$/ and File.file?(f) }
      # Add tests (eg test.svc) and add appropriate sub-dirs to
      # to those tests (eg test/)
      tests.each { |t|
        newSvc = addService(t).fetch(-1)
        t[".svc"] = ""
        sub_tests = dirs.select { |d| d = t }
        sub_tests.each { |d|
          newSvc.addMetaService(d)
          dirs.delete_if { |td| td = d }
        }
      }
      # add more meta-services (seems silly? oh well, give users more rope)
      dirs.each { |d| addMetaService(d) }
    end

    def addService(test)
      @subService << Service(test)
    end

    def addMetaService(test)
      @subService << MetaService(test)
    end

    def run()
      @subService.collect { |test| test.run }
    end
  end

  class Service < MetaService
    def initialize(file)
      testname = file.split("/").pop
      testname[".svc"] = ""
      super(file, testname)
    end

    def run()
      res = super()
      res << "OMG: #{@dir} #{@name}"
      return res
    end
  end

end

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

    def init(text)
      if @session.session_data['ServiceContainer'].nil?
        @session.session_data['ServiceContainer'] = ServiceTests::ServiceContainer.new(@session)
      end
      super(text)
    end

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

      sc = @session.session_data['ServiceContainer']
      svcs = sc.list.collect { |svc| svc.name }
      say("list of services:\n" + svcs.join("\n"))
    end
  end

  class ServiceAddCommand < Command
    self.command_name = 'service add'
    self.acl = BotCommands.allowInternalService
    self.handlePrivately = false
    self.short_desc = "add service watches"
    self.help_text = "add service watches from directory
service add /path/to/dir/"
    CommandList.addCommandClass(ServiceAddCommand)
    def run (text)
      command = text.split
      cmd = command.shift
      sub_cmd = command.shift

      @session.session_data['ServiceContainer'].addDir(command)
    end
  end

end
