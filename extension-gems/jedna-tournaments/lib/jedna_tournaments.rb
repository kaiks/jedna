# frozen_string_literal: true

require 'jedna'
require 'json'
require 'timeout'

require_relative 'jedna_tournaments/version'
require_relative 'jedna_tournaments/base_agent'
require_relative 'jedna_tournaments/process_agent'

module JednaTournaments
  class Error < StandardError; end
  class AgentError < Error; end
  class TimeoutError < AgentError; end
  
  class << self
    attr_accessor :configuration
  end
  
  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration)
  end
  
  class Configuration
    attr_accessor :timeout, :log_games, :log_dir, :parallel, :max_threads
    
    def initialize
      @timeout = 5.0
      @log_games = false
      @log_dir = './logs'
      @parallel = false
      @max_threads = 4
    end
  end
  
  # Set default configuration
  configure {}
end