# Basic handler for HiRISE/PIRL hosts
# All your base ... R belong 2 us!
# This file is meant to contain base class code that gets overitten by subclasses
# in other files. Sometimes the distinction between a base class and another class
# isn't clear in which case we go with code maturity. More mature code goes here.
#

require 'xmpp4r/client'
require 'xmpp4r/bytestreams'
require 'xmpp4r/caps'
require 'xmpp4r/muc'
require 'xmpp4r/roster'

require 'configbot/bghandler'

# Would be nice: http://xmpp.org/extensions/xep-0156.html
# Would be cool: http://xmpp.org/extensions/xep-0158.html

module HiBot

  @@CONFIGBOT_VERSION = "0.0.9"
  def self.CONFIGBOT_VERSION; @@CONFIGBOT_VERSION; end

  # Given a connection to a jabber server, handle messages as they come in
  # Messages are sent to objects that keep state per jid (or per nick in a MUC)
  class BotHandler < Jabber::Client
    # Client Connection to Jabber Server
    attr_reader :auth_info    # hash of jid/password/server
    attr_reader :mucs         # hash of muc JIDs => muc objects
    attr_reader :status_text
    attr_reader :mainthread   # the thread of the initializing process
    attr_reader :helpers      # A hash of helper objects
    attr_reader :sessions     # A hash of jid => session mappings

    def initialize(jid, password, server, muc_jid, status = 'Wow ... nice Botty')
      super(jid)
      @auth_info = {}
      @auth_info[:jid] = Jabber::JID.new(jid)
      @auth_info[:password] = password
      @auth_info[:server] = server
      @auth_info[:admin_muc_jid] = Jabber::JID.new(muc_jid)
      @status_text = status
      @mainthread = Thread.current
      @helpers = {}
      @sessions = {}
      @mucs = {}
      # Jabber::debug = true
      # Jabber::debug = false

      connect()
    end

    # Authenticate using the default creds
    def auth(password = @auth_info[:password])
      super(password)
    end

    def cleanup(msg=nil)
      @mainthread.wakeup
      close
    end

    # wrap connection-time initialization up into connect
    # TODO: handle disconnects cleanly
    def connect(server = @auth_info[:server])
      super(server)
      auth()
      init_capabilities()
      init_roster()
      init_file_helper()
      init_responses()
      init_admin_MUC()
    end

    # Example argument: Jabber::JID.new("room@conference.exmaple.com")
    def connectMUC(muc_jid)
      # Connect to the jabber server
      muc_prefix = Jabber::JID.new("#{muc_jid.node}@#{muc_jid.domain}")
      muc_nick = @auth_info[:jid].resource

      #Connect to the MUC!
      muc = HiBot::ResilientMUCClient.new(self, "#{muc_prefix}/#{muc_nick}", 10)

      # Get a MUC session
      session = getSession( muc_prefix, muc )

      muc.on_join do |time,nick|
        # session.joinedRoom(nick.downcase.split(".")[0])
        session.joinedRoom(nick)
      end

      muc.on_leave do |time,nick|
        # session.leftRoom(nick.downcase.split(".")[0])
        session.leftRoom(nick)
        # Anytime a user leaves, someone else could take over the same nick
        deleteSession( "#{muc_prefix}/#{nick}", muc )
      end

      # define simple callbacks to handle messages
      muc.on_private_message do |time,nick,text|
        priv_session = getSession( "#{muc_prefix}/#{nick}", muc )
        priv_session.user_role = muc.role( nick )
        priv_session.handle( text )
      end

      muc.on_message { |time,nick,text|
        # Kind of silly .. if we are ignoring time then why pass it?
	session.handleRoom( time, nick, text ) unless time
      }

      @mucs[ muc_prefix ] = muc
    end

    # Gets an existing session (or creates a new one)
    def getSession( jid, muc = nil )
      # Make sure we are dealing with JID objects ... everything else is sloppy
      if ! jid.kind_of? Jabber::JID
        jid = Jabber::JID.new(jid)
      end
      if ! @sessions[ jid ]
        @sessions[ jid ] = newSession( jid, muc )
      end
      return @sessions[ jid ]
    end

    # Gets an existing session (or creates a new one)
    def deleteSession( jid, muc = nil )
      # Make sure we are dealing with JID objects ... everything else is sloppy
      if ! jid.kind_of? Jabber::JID
        jid = Jabber::JID.new(jid)
      end
      if @sessions[ jid ]
        @sessions.delete( jid )
      end
    end

    def init_activity()
      # http://xmpp.org/extensions/xep-0108.html#schema
      # add_cap( 'http://jabber.org/protocol/activity' )
    end

    def init_admin_MUC()
      connectMUC( @auth_info[:admin_muc_jid] )
      add_cap("http://jabber.org/protocol/muc")
      add_cap("http://jabber.org/protocol/muc#user")
      add_cap("http://jabber.org/protocol/muc#admin")
      add_cap("http://jabber.org/protocol/muc#owner")
      add_cap("http://jabber.org/protocol/muc#unique")
      # http://xmpp.org/extensions/xep-0249.html#schema
      # add_feature( 'jabber:x:conference' )
    end

    def init_capabilities()
      @helpers[:caps] = Jabber::Caps::Helper.new(self)
      add_cap('http://jabber.org/protocol/caps')
      add_cap('http://jabber.org/protocol/disco#info')
      add_cap('http://jabber.org/protocol/disco#items')
    end
    def add_cap(url)
      @helpers[:caps].features << Jabber::Discovery::Feature.new( url )
    end

    def init_chat_state()
      # http://xmpp.org/extensions/xep-0085.html
      # add_cap( 'http://jabber.org/protocol/chatstates' )
    end

    # Commands and remote control
    def init_commands()
      # http://xmpp.org/extensions/xep-0050.html#schema
      # http://xmpp.org/extensions/xep-0146.html
      # add_cap( 'http://jabber.org/protocol/commands' )
    end

    def init_data_forms()
      # http://xmpp.org/extensions/xep-0068.html
      # http://xmpp.org/extensions/xep-0122.html
      # http://xmpp.org/extensions/xep-0141.html
      # add_cap( 'http://jabber.org/protocol/xdata-validate' )
      # add_cap( 'http://jabber.org/protocol/xdata-layout' )
    end

    def init_file_helper()
      @helpers[:files] = FileHandler.new( self )
      @helpers[:files].add_incoming_callback { |iq,file|
        from = Jabber::JID.new(iq.from)
        session = getSession( from )
        # Call session.incomingFile which then calls back incomingFile
        # if it will allow the file transfer. If it doesn't allow transfers
        # then it will simply return false
    if ! session.incomingFile( iq, file, @helpers[:files] )
          @helpers[:files].decline( iq )
        end
      }
      add_cap( 'http://jabber.org/protocol/bytestreams' )
      # TODO: see if UDP is supported here?
      # add_cap( 'http://jabber.org/protocol/bytestreams#udp' )
      add_cap( 'http://jabber.org/protocol/ibb' )
      add_cap( 'http://jabber.org/protocol/si' )
      add_cap( 'http://jabber.org/protocol/si/profile/file-transfer' )
      # http://xmpp.org/extensions/xep-0214.html#schema
      # add_feature( 'http://jabber.org/protocol/si/profile/fileshare' )
    end

    def init_jingle()
      # http://xmpp.org/extensions/xep-0166.html
      # http://xmpp.org/extensions/xep-0167.html
      # add_feature( 'urn:xmpp:jingle:1' )
      # add_feature( 'urn:xmpp:jingle:apps:rtp:1' )
      # add_feature( 'urn:xmpp:jingle:apps:rtp:audio' )
      # add_feature( 'urn:xmpp:jingle:apps:rtp:video' )

      # http://xmpp.org/extensions/xep-0176.html
      # http://xmpp.org/extensions/xep-0177.html
      # add_feature( 'urn:xmpp:jingle:1' )
      # add_feature( 'urn:xmpp:jingle:transports:ice-udp:0' )
      # add_feature( 'urn:xmpp:jingle:transports:ice-udp:1' )
      # add_feature( 'urn:xmpp:jingle:apps:rtp:1' )
      # add_feature( 'urn:xmpp:jingle:apps:rtp:audio' )
      # add_feature( 'urn:xmpp:jingle:apps:rtp:video' )
    end

    def init_mood()
      # http://xmpp.org/extensions/xep-0107.html#schema
      # add_cap( 'http://jabber.org/protocol/mood' )
      # and for more fun ...
      # http://xmpp.org/extensions/xep-0148.html#disco-other
      # add_cap( 'jabber:iq:iq' )
    end

    def init_oobd()
      # http://xmpp.org/extensions/xep-0066.html
      # add_cap( 'jabber:iq:oob' )
    end

    def init_ping()
      # http://xmpp.org/extensions/xep-0199.html
      # add_feature( 'urn:xmpp:ping' )
      # http://xmpp.org/extensions/xep-0224.html#schema
      # add_feature( 'urn:xmpp:attention:0' )
    end

    def init_presence()
      Thread.new {
        while true do
          presence = Jabber::Presence.new( :chat, @status_text, 1 )
          self.send( presence )
          sleep( 90 )
        end
      }
    end

    def init_responses()
      # Setup closure as a message callback handler 
      # Allow each session to handle their own messages
      add_message_callback do |m|
        session = getSession( m.from )
        if m.type != :error
          session.handle(m.body)
        else
          puts m
          #session.handleError(m)
        end
      end
    end

    def init_roster()
      @helpers[:roster] = AutoRoster.new(self)
      init_presence()
      # http://xmpp.org/extensions/xep-0145.html
      # add_cap( 'storage:rosternotes' )
    end

    def init_soap()
      # http://xmpp.org/extensions/xep-0072.html
      # add_cap( 'http://jabber.org/protocol/soap' )
    end

    def init_user_avatar()
      # http://xmpp.org/extensions/xep-0084.html#disco
      # add_cap( ... )
      # http://xmpp.org/extensions/xep-0153.html
    end

    def init_user_location()
      # http://xmpp.org/extensions/xep-0080.html#schema
      # add_cap( 'http://jabber.org/protocol/geoloc' )
    end

    # Attempts to identify what we are talking with (human/room/bot/...) based on the roster
    # defaults to :unknown
    def jid_type( jid )
      type = @helpers[:roster].jid_type( jid )
      if ! type
        muc = @mucs[ jid.strip ]
        if muc
    	    if muc.role(jid.resource) == :moderator 
            type = :admin
          else
            type = :bot
          end
        end
      end
      type = :unknown if ! type
      type
    end

    # Let's create a new session with the appropriate type
    def newSession( jid, muc )
      if muc == nil
        presence = @helpers[:roster].items[ jid ]
        print "presence: #{presence}\n"
        session = SessionHandler.new( self, jid )
      else
        session = MUCSessionHandler.new( self, jid, muc )
      end
      # TODO: decorate session appropriately
      return session
    end

    def incomingFile( iq, file, session, attrs = {} )
      session.say( "TODO: deal with incoming transfers" )
      @helpers[:files].decline( iq )
    end

  end

  # Just add everyone/everything that speaks
  # Additionally, setup access based on which group a user is in
  #  -- Admin: can do anything
  #  -- Default: can't do anything
  class AutoRoster < Jabber::Roster::Helper
    def initialize(stream, startnow = true)
      super(stream, startnow)

      # Whenever someone unsubscribes from us, we'll do the same
      add_subscription_callback do |rosterItem,pStanza|
        puts "subscription callback: #{pStanza}"
      end

      # whenever someone wants to subscribe, we will let them
      add_subscription_request_callback do |rosterItem,presence|
        puts "subscription_request_callback: #{rosterItem}"
        accept_subscription(presence.from)
        if ! subscribed(presence.from)
          add(presence.from, nil, true)
          rosterItem.subscribe()
          rosterItem.send()
        end
      end

      add_presence_callback(2) do |rosterItem,oldPresence,newPresence|
      end

    end

    def jid_type(jid)
      return :admin_muc if BotCommands.AdminMUC.include?( "#{jid}" )
      return :admin     if BotCommands.AdminJID.include?( "#{jid.strip}" )
      rosterItem = self.items[ jid ]
      return :bot       if rosterItem and rosterItem.iname == "bot"

      # No idea ... punt!
      nil
    end

    # Are we subscribed to a user?
    def subscribed(jid)
      rosterUsers = find(jid)
      rosterUsers.each do |m|
        # For now just assume that if they are in our buddy list then we are subscribed
        return true
      end
      return false
    end
  end

  # A response handler is given some input and then generates some form of output. Each
  # chat session is typically given its own response handler
  class ResponseHandler
    attr_reader :opts             # A useful way of keeping internal state
    attr_reader :client           # A reference to the top level bot
    attr_reader :sess             # A reference to some session handler
                                  # (so we can @sess.say(things))
    attr_accessor :acl_criteria   # Passed to each command for ACL verification

    def initialize( client, sessionHandler )
      @opts = {}
      @client = client
      @sess = sessionHandler
      init_acl_criteria( {} )
    end

    def init_acl_criteria( acl_criteria )
      if @sess.kind_of?(HiBot::MUCSessionHandler)
        session_type = :muc
        target_nick = @sess.target_nick
        if target_nick != nil && target_nick.length > 0
          session_type = :muc_private
        end
      else
        session_type = :private
      end

      @acl_criteria = {
        :jid => @sess.target_jid.strip,
        :full_jid => @sess.target_jid,
        :session_type => session_type,
        :bot_type => :configbot
      }
      # Use/override defaults with provided values
      acl_criteria.map { |k,v| @acl_criteria[k] = v }
    end

    # Simple one-one chat
    def handle(text)
    end

    # more complex, some responses require a private session
    def handleRoom(text, priv_sess)
    end

    def say(text)
      @sess.say(text)
    end

    def user_role=(value)
      @acl_criteria[ :user_role ] = value
    end

    # Returns true if a message should be handled privately (WRT MUC)
    def handlePrivately?(text)
      return false
    end
  end

  # How are files handled?
  class FileHandler < Jabber::FileTransfer::Helper
    attr_reader :client

    def initialize( client )
      super(client)
      @client = client
    end

    def incoming_file(iq, file)
      Thread.new begin
        puts "accepting file from #{iq.from} (#{file.fname})"
        bs = accept(iq)
        if bs == nil
          say("Could not get a valid byte stream", JID.new(iq.from).resource)
          return
        end

        if bs.kind_of?(Jabber::Bytestreams::SOCKS5Bytestreams)
          bs.connect_timeout = 10
          bs.add_streamhost_callback { |streamhost,state,e|
            case state
              when :connecting
                puts "Connecting to #{streamhost.jid} (#{streamhost.host}:#{streamhost.port})"
              when :success
                puts "Successfully using #{streamhost.jid} (#{streamhost.host}:#{streamhost.port})"
              when :failure
                puts "Error using #{streamhost.jid} (#{streamhost.host}:#{streamhost.port}): #{e}"
            end
          }
        end

        if ! bs.accept
          say("Byte stream failed to accept", JID.new(iq.from).resource)
          # Last-ditch effort to tell the client to give up
          decline(iq)
          return
        end

        while buf = bs.read() != nil
          puts ". #{buf}"
        end
        bs.close
      end
    end

  end

  # defines a generic way to communicate back
  class SessionHandler
    attr_reader :client
    attr_reader :target_jid
    # alias :real_extend :extend
    # hash of nicks that we don't ignore

    def initialize(client, target_jid)
      @client = client
      @target_jid = target_jid
      @resp = ResponseHandler.new( @client, self )
    end

    def handle( text )
      @resp.handle(text)
    end

    def cleanup( text )
      @resp.cleanup( text )
    end

    def say(text, mesg_type = :chat)
      mesg = Jabber::Message.new(@target_jid, text)
      mesg.type = mesg_type
      @client.send( mesg )
    end

    # A helper for bot detection
    def jid_type( jid )
      @client.jid_type( jid )
    end
    def bot_list( )
      roster = @client.helpers[:roster]
      roster.items.keys
    end
    def user_role=( value )
      @resp.user_role = value
    end

    def newRS( someClass )
      @resp = someClass.new( @client, self )
    end
  end

  class MUCSessionHandler < SessionHandler
    attr_reader :muc
    attr_reader :muc_jid
    attr_reader :target_nick # this is the resource portion of the target_jid
    attr_reader :allowed_nicks
    attr_reader :muc_roster

    def initialize( client, target_jid, muc )
      super(client, target_jid)
      @muc = muc
      @muc_jid     = target_jid.strip
      @target_nick = target_jid.resource
      @allowed_nicks = {}
      @muc_roster = Array.new
    end

    def joinedRoom(nick)
      @muc_roster.push(nick)
      @resp.joinedRoom( nick )
    end

    def leftRoom(nick)
      @muc_roster.delete(nick)
      @resp.leftRoom( nick )
    end

    # Only called for a room-level MUCSessionHandler and never for a private
    # MUCResponseHandler instance
    def handleRoom( time, nick, text )
      if !time and @resp.roomCan?(text, nick)
        if @resp.handlePrivately?( text )
          priv_session = @client.getSession( "#{@muc_jid}/#{nick}", @muc )
          priv_session.handle( text )
        else
          @resp.handle( text )
        end
      end
    end

    def bot_list( )
      participants = @muc_roster.reject { |nick| @muc.role(nick) != :participant }
      participants.map { |nick| "#{@muc_jid}/#{nick}" }
    end

    def say(text, mesg_type = :chat)
      @muc.say( text, @target_nick )
    end
  end

  class ResilientMUCClient < Jabber::MUC::SimpleMUCClient
    attr_reader :sched_thread
    attr_reader :reconnectJID
    attr_reader :delayTime

    def initialize( jabberClient, jid, reconnectInterval=10 )
      super( jabberClient )
      @reconnectJID = jid
      @sched_thread = Thread.new { self.schedule() }
      @delayTime = reconnectInterval
      @disconnect = false
    end
    def join(jid, password=nil)
      if active?
        raise "MUCClient already active"
      end
      @jid = (jid.kind_of?(Jabber::JID) ? jid : Jabber::JID.new(jid))
      activate
      # Joining
      pres = Jabber::Presence.new
      pres.to = @jid
      pres.from = @my_jid
      xmuc = Jabber::MUC::XMUC.new
      xmuc.password = password
      xmuc.add_element 'history', {'maxchars'=>'0'}
      pres.add(xmuc)

      # We don't use Stream#send_with_id here as it's unknown
      # if the MUC component *always* uses our stanza id.
      error = nil
      @stream.send(pres) { |r|
       if from_room?(r.from) and r.kind_of?(Jabber::Presence) and r.type == :error
        # Error from room
        error = r.error
        true
       # type='unavailable' may occur when the MUC kills our previous instance,
       # but all join-failures should be type='error'
       elsif r.from == jid and r.kind_of?(Jabber::Presence) and r.type != :unavailable
        # Our own presence reflected back - success
        if r.x(Jabber::MUC::XMUCUser) and (i = r.x(Jabber::MUC::XMUCUser).items.first)
          @affiliation = i.affiliation  # we're interested in if it's :owner
          @role = i.role                # :moderator ?
        end

        handle_presence(r, false)
        true
       else
        # Everything else
        false
       end
      }

      if error
       deactivate
       raise ServerError.new(error)
      end

      self
    end
    # TODO: implement an actual disconnect
    def disconnect(); @disconnect = true; end

    def role( nick )
      if ! self.roster.include?(nick)
        return nil
      end
      newNickInfo = self.roster[nick].x('http://jabber.org/protocol/muc#user')
      if ! newNickInfo
        return nil
      end
      return newNickInfo.first_element('item').role
    end

    def schedule()
      while( ! @disconnect )
	if ! self.active?()
	  print "joining MUC again ... \n"
	  begin
	    self.join( @reconnectJID )
	  rescue Exception=>e
	  end
	end
	sleep @delayTime
      end
    end
  end

end

# Adds aggregate handler functionality and uses the classes defined above
require 'configbot/aggrhandler'

#Overwriting add_presence function to remove the most likely unnecessary sort! function
module Jabber
  module Roster
    class Helper
      class RosterItem
	     alias :old_add_presence :add_presence
        def add_presence(newpres)
          @presences_lock.synchronize {
            # Delete old presences with the same JID
            @presences.delete_if do |pres|
              pres.from == newpres.from or pres.from.resource.nil?
            end

            if newpres.type == :error and newpres.from.resource.nil?
              # Replace by single error presence
              @presences = [newpres]
            else
              # Add new presence
              @presences.push(newpres)
            end
				#Removing this line.  Causes huge cpu (and maybe memory) hit 
            #@presences.sort!  
          }
        end
		end
    end
  end 
end
