# Aggregate responses from many nodes back to a single source

module HiBot

  class AggregatorHelpers

    class << self

      def node_shorthand( node_list )
        # default representation
        node_list.sort!
        representation = node_list.join(", ").downcase
        [ self.method(:node_shorthand_ranges),
          # self.method(:node_shorthand_all)
        ].each {
        |fun|
          tmp_rep = fun.call(node_list)
          # @session.say("REPR: #{tmp_rep}")
          # use shortest representation
          if tmp_rep.length < representation.length
            representation = tmp_rep
          end
        }
        # @session.say("FINAL REPR: #{representation}")
        return representation
      end

      def node_shorthand_ranges( node_list )
        # represent hosts by their ranges.
        # eg: "cnode01, cnode02, cnode03" becomes "cnode[1-3]"
        combined = {}
        node_list.map { |node|
          split_boundary=node.index(/([0-9]+)$/)
        if split_boundary == nil
          base = node
          num = ''
        else
          base = node.slice(0,split_boundary)
          num = node[/[0-9]+$/]
        end
        if ! combined.has_key?(base)
          combined[base] = []
        end
        combined[base].push( num )
        }
        ret_list = []
        combined.each_pair { |base,range|
        if range.length == 1
          pretty_range = range[0]
        else
          pretty_range = "[#{self.shorten_range(range)}]"
        end
        ret_list.push( "#{base}#{pretty_range}" )
          # @session.say("name: #{base}#{pretty_range}")
        }
        ret_list.sort!
        return ret_list.join(", ")
      end

      # Takes a list [0,1,2,3, 5,6,7 ... n ] and turns it into a short version [0-3, 5-n]
      def shorten_range( range_list )
        int_range = range_list.map { |item| item.to_i }
        first_val = nil
        last_val = nil
        ret_list = []
        int_range.sort.each { |current_val|
          first_val = current_val if first_val == nil
          if last_val == nil
            # no values seen yet
            last_val = current_val
          elsif current_val == last_val + 1
            # next in sequence? ... if so then just iterate
            last_val = current_val
          else
            # not next, then close old sequence
            if first_val != last_val and last_val != nil
              ret_list.push( "#{first_val}-#{last_val}" )
            else
              ret_list.push( "#{first_val}" )
            end
            first_val = current_val
            last_val = nil
          end
        }
        # Sequence not closed
        if first_val != nil
          if first_val != last_val and last_val != nil
            ret_list.push( "#{first_val}-#{last_val}" )
          else
            ret_list.push( "#{first_val}" )
          end
        end
        return ret_list.join(", ")
      end

      def node_shorthand_all( node_list, all )
        all_but = @finished - node_list
        if all_but.length == 0
          return "All nodes"
        end
        all_but = node_shorthand_ranges( all_but )
        return "All except #{all_but}"
      end

    end

  end

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

    def initialize(session, msg_timeout = 2, max_delay = 12, bot_list = false)
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
      if (!bot_list)
        @bot_list = @session.bot_list
      else
        @bot_list= bot_list
      end
      
      #@bot_list = bot_list
      #if @session.kind_of?(HiBot::MUCSessionHandler)
      #  @bot_list.map! { |jid| jid.split("/").pop }
      #end
      # print "Bot list: #{@bot_list.sort.join(", ")}\n"

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
        node_spec = AggregatorHelpers.node_shorthand( nodes.sort )
      @session.say( "#{node_spec} said:\n#{text.strip}\n" )
        true
      }
    end

    # release stats
    def purgeFinal()
      desc = Aggregator.getDescFromID( @aid )
      bot_list = @bot_list
      if bot_list.kind_of?(Array)
        bot_list.map! { |jid| jid.split("/").pop }
      end
      no_finish = bot_list.sort - @finished
      no_output = @finished.sort - @responded.keys
      @session.say( "#{@finished.length}/#{@bot_list.length} nodes have completed #{desc} (id=#{@aid})" )
      @session.say( "Finished with no output: #{AggregatorHelpers.node_shorthand(no_output)}" ) unless no_output.empty?
      @session.say( "Didn't finish: #{AggregatorHelpers.node_shorthand(no_finish)}" ) unless no_finish.empty?
    end

  end

  # Aggregate responses from multiple sessions into one location
  class AggregateResponseHandler < ResponseHandler
    def isNumeric(s)
      Float(s) != nil rescue false
    end
    def handle(text)
      rid = text.split(" ").shift
      rid = rid.split("=").pop
      if (isNumeric(rid))
        text[ "rid=#{rid} " ] = ""
      end
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
