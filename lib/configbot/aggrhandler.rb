# Aggregate responses from many nodes back to a single source

module HiBot

  class Aggregator
    # Class static vars to keep track of aggregator instances
    @@ids = {}
    @@desc = {}
    @@next_id = 0

    class << self
      def addResponse( id, src, text )
        return unless @@ids[ id ]
	@@ids[ id ].addResponse( src, text )
      end
      def addKeepAlive( id, src )
        return unless @@ids[ id ]
	@@ids[ id ].addKeepAlive( src )
      end
      def addFin( id, src )
        return unless @@ids[ id ]
	@@ids[ id ].addFin( src )
      end
      def newID( *args )
        description = args.shift
        obj = Aggregator.new( *args )
	@@ids[ obj.aid ] = obj
	@@desc[ obj.aid ] = description
	obj.aid
      end
      def finishID( aid )
        @@ids.delete( aid )
      end
      def getDescFromID( aid )
	@@desc[ aid ]
      end
    end

    attr_reader :aid # The id of an aggregator instance

    def initialize(session, msg_timeout = 2, max_delay = 6)
      @session = session
      @msg_timeout = msg_timeout
      @max_delay = max_delay
      @purged = false
      @aid = "#{@@next_id}"
      @@next_id += 1

      @response_text = {}
      @responded = {}
      @finished = []

      # The initial bot list for when the aggregator is started
      @bot_list = @session.bot_list
      if @session.kind_of?(HiBot::MUCSessionHandler)
        @bot_list.map! { |jid| jid.split("/").pop }
      end
      print "Bot list: #{@bot_list.sort.join(", ")}\n"

      @delay_thread = Thread.new {
        sleep( @max_delay )
	self.purge
      }
      reset_wait()
      # reset_auto_destruct()
    end

    def addResponse( src, text )
      reset_wait()
      @response_text[ text ] = [] unless @response_text[ text ]
      @response_text[ text ].push( src )
      @responded[ src ] = 0 unless @responded[ src ]
      @responded[ src ] += 1
    end

    def addFin( src )
      # src finished output ...
      @finished.push( src )
      # Everybody is done? Let's not wait around for the cows to come home...
      if @finished.length == @bot_list.length
	@wait_thread.kill     if @wait_thread
	@destruct_thread.kill if @destruct_thread
        purge()
	purgeFinal()
      else
        reset_wait()
      end
    end

    def addKeepAlive( src )
      reset_auto_destruct()
    end

    def reset_auto_destruct()
      @destruct_thread.kill if @destruct_thread
      timeo = (@msg_timeout > 10) ? @msg_timeout + 1 : 11
      @destruct_thread = Thread.new {
        sleep( timeo )
	self.purgeFinal
        Aggregator.finish( @aid )
      }
    end

    def reset_wait()
      reset_auto_destruct()
      @wait_thread.kill if @wait_thread
      @wait_thread = Thread.new {
        sleep( @msg_timeout )
	self.purge
      }
    end

    # release aggregated messages
    def purge()
      @response_text.delete_if { |text,nodes|
	@session.say( "#{nodes.sort.join(", ")} said:\n#{text}\n" )
        true
      }
    end

    # release stats
    def purgeFinal()
      desc = Aggregator.getDescFromID( @aid )
      no_finish = @bot_list.sort - @finished
      no_output = @finished.sort - @responded.keys
      @session.say( "#{@finished.length}/#{@bot_list.length} nodes have completed #{desc}" )
      @session.say( "The following nodes finished with no output: #{no_output.join(" ")}\n" ) unless no_output.empty?
      @session.say( "The following nodes didn't finish: #{no_finish.join(" ")}\n" ) unless no_finish.empty?
    end

  end

  # Aggregate responses from multiple sessions into one location
  class AggregateResponseHandler < ResponseHandler
    def handle(text)
      rid = text.split(" ").shift
      rid = rid.split("=").pop
      text[ "rid=#{rid} " ] = ""
      src = @sess.target_jid
      if @sess.kind_of?(HiBot::MUCSessionHandler)
        src = @sess.target_nick
      end
      if text == "keep-alive"
        Aggregator.addKeepAlive( rid, src )
      elsif text.split(" ")[0] == "fin"
        Aggregator.addFin( rid, src )
      else
        Aggregator.addResponse( rid, src, text )
      end
    end
  end

end
