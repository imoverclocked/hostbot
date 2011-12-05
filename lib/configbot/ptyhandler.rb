#
# This seems very unreliable for the purposes I was going for in the first place:
#   Watching for wall message on a host. It's probably better to watch perticular logs
#

OMG WTF BBQ

require 'pty'

module PTYHandler

  class WatchPTY
    attr_reader :pty
    attr_reader :session
    attr_reader :thread

    def initialize( session )
      @session = session
      print "SESSION: #{@session}\n"
      @thread = Thread.new {
        print "new thread ...\n"
        res = PTY.spawn("/usr/bin/login -f root") { |m,s|
          print "INSIDE PTY.open...\n"
          print "Opened pty #{m.path} -- #{s.path}\n"
          while ( str = m.gets )
            print "GOT STRING: #{str}\n"
          end
          print "done with loop #{str}\n"
        }
        print "done w/PTY.spawn res: #{res}\n"
      }
    end

    def getSession()
      return @session
    end

    def join()
      @thread.join()
    end

  end

end
