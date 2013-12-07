#
# A framework and implementation of Commands with ACLs
#

module BotCommands
  @@AdminJID = ['tims@uahirise.org', 'kfine@uahirise.org']
  def self.AdminJID; @@AdminJID; end
  @@AdminMUC = ['hostbots@conference.uahirise.org', 'hostbots-dev@conference.uahirise.org']
  def self.AdminMUC; @@AdminMUC; end

  # "ACLMatchAll" ... match all items given to this ACL
  class ACL
    attr_reader :criteria #Array of ACLItems

    # bring ACLs together to be more (&) or less (|) restrictive.
    def &(otherACL)
      return ACL.new( self, otherACL )
    end
    def |(otherACL)
      return ACLMatchAny.new( self, otherACL )
    end

    def to_s
      to_str
    end

    def to_str
      begin
        "ACL( " + @criteria.map{ |a| a.to_str }.join(", ") + ")"
      rescue Exception => e
	raise "ACL--BAD--( " + @criteria.map{ |a| a.respond_to?(:to_str) and a.to_str or a.inspect }.join(", ") + ") -- #{e.backtrace}"
      end
    end

    # Given an Array of ACLItems
    def initialize( *criteria )
      if criteria.kind_of?(Array)
        @criteria = criteria
	# ensure that all parameters are ACL objects
	criteria.each { |acl| acl.is_a?(BotCommands::ACL) or acl.is_a?(BotCommands::ACLItem) or raise "bad ACL parameters: (#{acl}) #{acl.inspect}" }
      else
        @criteria = [ criteria ]
	# ensure that the parameter is an ACL object
	criteria.is_a?(BotCommands::ACL) or criteria.is_a?(BotCommands::ACLItem) or raise "bad ACL parameter: #{criteria.inspect}"
      end
    end

    # Given all criteria, does this ACL pass?
    def can?( criteria )
      # On the first item to fail, fail the ACL
      @criteria.each { |crit|
        if ! crit.can?( criteria )
          #print "     Failed criteria: #{crit}\n"
          #print "            criteria: "
          #print criteria
          #print "\n"
          return false
        end
      }
      # If nothing fails, pass
      return true
    end

    # Does one of the provided criteria prohibit the use of this ACL?
    #  -- used to filter out commands for known criteria such as a
    #     muc session/private muc session/private session 
    def might?( criteria )
      # If anyone says "no" then the deal is off...
      @criteria.each { |crit|
        if ! crit.might?( criteria )
          return false
        end
      }
      # If we might ... we might
      return true
    end

    def to_s()
      print "[ #{self.class}:\n\t#{@criteria.join(",\n\t")} ]\n"
    end

  end

  class ACLMatchAny < ACL

    def to_str
      begin
        "ACLMatchAny( " + @criteria.map{ |a| a.to_str }.join(", ") + ")"
      rescue Exception => e
	raise "ACLMatchAny--BAD--( " + @criteria.map{ |a| a.respond_to?(:to_str) and a.to_str or a.inspect }.join(", ") + ") -- #{e.backtrace}"
      end
    end

    # Given all criteria, does this ACL pass?
    def can?( criteria )
      # On the first item to pass, pass the ACL
      @criteria.each { |crit|
        if crit.can?( criteria )
          return true
        else
          #print "Didn't pass criteria: #{@criteria}\n"
        end
      }
      #print "     Failed criteria: #{@criteria}\n"
      #print "            criteria: "
      #print criteria
      #print "\n"
      return false
    end

    # Does one of the provided criteria prohibit the use of this ACL?
    #  -- used to filter out commands for known criteria such as a
    #     muc session/private muc session/private session 
    def might?( criteria )
      @criteria.each { |crit|
        if crit.might?( criteria )
          return true
        end
      }
      # nobody thinks we might match ... I guess we will never match
      return false
    end

  end

  class ACLItem
    attr_reader :logic_method   # and/or/nand/nor/xor
    attr_reader :keyword        # identifier for item: username/sessionType/messageType/...
    attr_reader :allowed_values
    attr_reader :logic_mappings

    # Must be called before initialize(super) by subclasses
    def addMapping( logic_type, method )
      @logic_mappings[ logic_type ] = method
    end

    def to_s
      av = @allowed_values
      if av.kind_of?(Array)
        av = av.join( ", " )
      end
      "ACLItem( #{@logic_method}, #{@keyword}, [ #{av} ] )"
    end

    def to_str
      to_s
    end

    def initialize( logic_type, keyword, allowed_values = nil )
      # Default mappings
      @logic_mappings = {
        :and => :logic_and,
        :or => :logic_or,
        :nand => :logic_nand,
        :nor => :logic_nor
      }
      @logic_method = self.method(@logic_mappings[ logic_type ])
      @keyword = keyword

      # Allowed Values should always be an array
      if allowed_values == nil
        allowed_values = []
      elsif ! allowed_values.kind_of?( Array )
        allowed_values = [ allowed_values ]
      end
      @allowed_values = allowed_values
    end

    # Given the criteria, does this ACL pass?
    def can?( criteria )
      if criteria[ @keyword ] == nil
        # nil evaluates to false
        return nil
      end
      return @logic_method.call( criteria )
    end

    # Instead of looking to invalidate if some criteria doesn't exist, see if
    # could possibly allow given more criteria
    def might?( criteria )
      # This is a hard one to implement since we could technically add a value to the
      # list and then we would return true. However, if the value is being sent in we
      # should assume that is the value we are expecting to see in the case of this filter.
      can = can?( criteria )
      return ( (can == true) or (can == nil) ) == true
    end

    ########################################################
    # Implement the various logic forms given the criteria #
    ########################################################

    # we just need one value to be allowed in order to return true
    def logic_or( criteria )
      val = criteria[ @keyword ]
      if ! val.kind_of?(Array)
        val = [ val ]
      end
      val.each { |value|
        @allowed_values.each { |av|
          if value == av
            return true
          end
        }
      }
      return false
    end

    # We need all provided values to be true...
    def logic_and( criteria )
      val = criteria[ @keyword ]
      if ! val.kind_of?(Array)
        val = [ val ]
      end
      val.each { |value|
        if ! @allowed_values.include?( value )
          return false
        end
      }
      return true
    end

    # ... and so it was
    def logic_nand( criteria )
      return ! logic_and(criteria)
    end
    def logic_nor( criteria )
      return ! logic_or(criteria)
    end
  end

  # Instead of allowed values, we have denied values
  class NegativeACLItem < ACLItem
    def can?( criteria )
      return ! super( criteria )
    end
  end

  ###################################################
  # pre-defined ACLs for ease of command definition #
  ###################################################

  # Match anything
  def self.any_acl; @@any_acl; end
  @@any_acl = ACL.new()

  # Match nothing
  def self.none_acl; @@none_acl; end
  @@none_acl = ACLMatchAny.new()

  # Private MUC chat?
  def self.private_muc_acl; @@private_muc_acl; end
  @@private_muc_acl = ACL.new(
    ACLItem.new(:or, :session_type, :muc_private)
  )

  # public MUC chat?
  def self.public_muc_acl; @@public_muc_acl; end
  @@public_muc_acl = ACL.new(
    ACLItem.new(:or, :session_type, :muc)
  )

  # any kind of MUC chat?
  def self.muc_acl; @@muc_acl; end
  @@muc_acl = ACLMatchAny.new(
    public_muc_acl,
    private_muc_acl
  )

  # muc chat with a moderator?
  def self.muc_moderator_acl; @@muc_moderator_acl; end
  @@muc_moderator_acl = ACL.new(
    muc_acl,
    ACLItem.new(:or, :user_role, :moderator)
  )

  # direct chat? (directly between two entities or private through a room)
  def self.direct_acl; @@direct_acl; end
  @@direct_acl = ACL.new( NegativeACLItem.new( :or, :session_type, :muc ) )

  # private jid chat? (no room involved)
  def self.private_jid_acl; @@private_jid_acl; end
  @@private_jid_acl = ACL.new(ACLItem.new(:or, :session_type, :private))

  # TODO: deprecate and stop using this
  def self.admin_acl; @@admin_acl; end
  @@admin_acl = ACLMatchAny.new(
    # Listen to Administrative JIDs
    ACLItem.new(:or, :jid, BotCommands.AdminJID),
    # Listen to room moderators in private MUC
    ACL.new(
      ACLItem.new(:or, :jid, BotCommands.AdminMUC),
      ACLItem.new(:or, :session_type, :muc_private),
      muc_moderator_acl
    ),
    # Listen to room moderators in the room
    ACL.new(
      ACLItem.new(:or, :jid, BotCommands.AdminMUC),
      ACLItem.new(:or, :session_type, :muc),
      muc_moderator_acl
    )
  )

  class ACLCreator

    @@specialACL = {
      'any' => BotCommands.any_acl,
      'none' => BotCommands.none_acl,
      'public_muc' => BotCommands.public_muc_acl,
      'private_muc' => BotCommands.private_muc_acl,
      'private_jid' => BotCommands.private_jid_acl,
      'direct' => BotCommands.direct_acl,
      'muc_moderator' => BotCommands.muc_moderator_acl,
      'muc' => BotCommands.muc_acl,
    }

    def self.special( name, newACL = nil )
      if newACL != nil
	if @@specialACL.has_key?(name)
          raise "#{name} already defined as an ACL"
	end
	@@specialACL[name] = newACL
      end
      @@specialACL[name].nil? and raise "Undefined special acl name: #{name}"
      @@specialACL[name]
    end

    def self.muc( name )
      stripped_name = Jabber::JID.new(name).strip.to_s
      ACL.new(
        ACLItem.new(:or, :jid, stripped_name ),
        BotCommands.muc_acl
      )
    end

    def self.jid( name )
      stripped_name = Jabber::JID.new(name).strip.to_s
      ACL.new(
        ACLItem.new(:or, :jid, stripped_name ),
        @@specialACL['private_jid']
      )
    end

    @@type_mappings = {
      'special' => :special,
      'muc' => :muc,
      'jid' => :jid,
      'anyof' => :anyof,
    }

    def self.anyof( subACLs )
      acls = Array.new
      # print "subACLS: #{subACLs.inspect}\n"
      subACLs.each { |aclElem|
        aclElem.keys.each { |k|
	  m = self.method(@@type_mappings[ k ])
          acls.push(m.call(aclElem[k]))
	}
      }
      newACL = ACLMatchAny.new( *acls )
      newACL
    end

    # Assumes everything from the "acl:" tree is passed
    def self.mapFromYAML( yamlData )
      acls = Array.new
      yamlData.each { |aclElem|
        aclElem.keys.each { |k|
          m = self.method(@@type_mappings[ k ])
          acls.push(m.call(aclElem[k]))
	}
      }
      # print "yamlData: #{yamlData.inspect}\n"
      # print "acls: #{acls.inspect}\n"
      newACL = ACL.new( *acls )
      newACL
    end

  end

end
