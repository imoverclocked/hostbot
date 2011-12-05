#
# A background handler for events that need to happen after some period of time
#   DelayHandler - wait for some period of time and then do something
#     - can repeat a specified number of times. 0 means run once
#

module BGHandler

  class DelayHandler
    attr_reader :delayTime
    attr_reader :repeat
    attr_reader :session
    attr_reader :thread
    attr_reader :sched_thread
    attr_reader :runTimeO

    def initialize( delayTime, repeat, session, runTimeO = nil )
      @delayTime = delayTime
      @repeat = repeat
      @session = session
      @runTimeO = runTimeO
      @sched_thread = Thread.new { self.schedule() }
    end

    def run()
    end

    def getSession()
      return @session
    end

    def schedule()
      while @repeat >= 0:
        @repeat -= 1
        sleep( self.delayTime )
	@thread = Thread.new { self.safe_run() }
	@thread.join( self.delayTime )
      end
    end

    def join()
      @sched_thread.join()
    end

    # Run method in a try/catch style and report the exception (if any)
    def safe_run()
      begin
        self.run()
      rescue Exception=>e
	e_string = "hmm, cron method excepted: #{e}"
	print e_string
	self.getSession().say( e_string )
      end
    end

  end

  class CronHandler < BGHandler::DelayHandler
    def initialize(delayTime, session, runTimeO = nil)
      super(delayTime=delayTime, repeat=-1, session=session, runTimeO=runTimeO)
    end
    def schedule()
      while true
        sleep(self.delayTime)
	# Try and run something in a thread
	@thread = Thread.new { self.safe_run() }
	@thread.join( self.delayTime )
      end
    end
  end

end
