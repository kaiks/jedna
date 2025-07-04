require_relative '../interfaces/player_identity'

module Jedna
  class Player
    attr_accessor :hand
    attr_reader :identity
    
    def initialize(identity_or_nick)
      @joined = Time.now
      # Support both old string-based and new identity-based creation
      @identity = case identity_or_nick
                  when String
                    Jedna::IrcIdentity.new(identity_or_nick)
                  when Jedna::PlayerIdentity
                    identity_or_nick
                  else
                    raise ArgumentError, "Expected String or PlayerIdentity, got #{identity_or_nick.class}"
                  end
      require_relative 'hand'
      @hand = Hand.new
    end
  
    def to_s
      @identity.to_s
    end
  
    def ==(player)
      return false unless player.is_a?(Player)
      @identity.matches?(player.identity)
    end
    
    # Check if this player matches a given identity or string
    def matches?(identity_or_string)
      @identity.matches?(identity_or_string)
    end
  end
end
