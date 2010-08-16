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

    # Given an Array of ACLItems
    def initialize( *criteria )
      if criteria.kind_of?(Array)
        @criteria = criteria
      else
        @criteria = [ criteria ]
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

    def to_s()
      av = @allowed_values
      if av.kind_of?(Array)
        av = av.join( ", " )
      end
      "ACLItem( #{@logic_method}, #{@keyword}, [ #{av} ] )"
    end

    def initialize( logic_type, keyword, allowed_values = nil )
      # Default mappings
      @logic_mappings = {
        :and => :logic_and,
        :or => :logic_or,
        :nand => :logic_nand,
        :nor => :logic_nor
      }
      @logic_method = self.method(@logic_mappings[ logic_type ] )
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
  def self.admin_acl; @@admin_acl; end
  @@admin_acl = ACLMatchAny.new(
    # Listen to Administrative JIDs
    ACLItem.new(:or, :jid, BotCommands.AdminJID),
    # Listen to room moderators in private MUC
    ACL.new(
      ACLItem.new(:or, :jid, BotCommands.AdminMUC),
      ACLItem.new(:or, :session_type, :muc_private),
      ACLItem.new(:or, :user_role, :moderator)
    ),
    # Listen to room moderators in the room
    ACL.new(
      ACLItem.new(:or, :jid, BotCommands.AdminMUC),
      ACLItem.new(:or, :session_type, :muc),
      ACLItem.new(:or, :user_role, :moderator)
    )
  )

  def self.any_acl; @@any_acl; end
  @@any_acl = ACL.new()

  def self.private_acl; @@private_acl; end
  @@private_acl = ACL.new( NegativeACLItem.new( :or, :session_type, :muc ) )

end
