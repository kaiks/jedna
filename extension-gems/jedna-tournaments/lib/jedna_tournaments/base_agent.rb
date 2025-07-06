module JednaTournaments
  # Abstract base class for all agent implementations
  class BaseAgent
    attr_reader :name
    
    def initialize(name = nil)
      @name = name || self.class.name
    end
    
    # Start the agent
    def start
      raise NotImplementedError, "#{self.class} must implement #start"
    end
    
    # Stop the agent
    def stop
      raise NotImplementedError, "#{self.class} must implement #stop"
    end
    
    # Check if agent is running
    def running?
      raise NotImplementedError, "#{self.class} must implement #running?"
    end
    
    # Request an action from the agent
    def request_action(game_state, timeout: nil)
      raise NotImplementedError, "#{self.class} must implement #request_action"
    end
    
    # Send a notification to the agent
    def notify(message)
      raise NotImplementedError, "#{self.class} must implement #notify"
    end
    
    # Send a simple notification message
    def notify_message(text)
      notify_with_type('notification', message: text)
    end
    
    # Send an error notification to the agent
    def notify_error(error)
      notify_with_type('error', message: error)
    end
    
    # Send game end notification to the agent
    def notify_game_end(winner, scores)
      notify_with_type('game_end', winner: winner, scores: scores)
    end
    
    protected
    
    def notify_with_type(type, data)
      message = { type: type }.merge(data)
      notify(JSON.generate(message))
    end
  end
end