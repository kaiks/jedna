# frozen_string_literal: true

require 'jedna'
require 'json'
require 'timeout'

require_relative 'jedna_tournaments/version'
require_relative 'jedna_tournaments/base_agent'
require_relative 'jedna_tournaments/process_agent'

# Process-backed agent support for Jedna tournaments.
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

  # Runtime settings consumed by ProcessAgent.
  class Configuration
    attr_accessor :timeout

    def initialize
      @timeout = 5.0
    end
  end

  # Set default configuration
  configure {}
end
