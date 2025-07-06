require 'open3'
require 'json'
require 'timeout'

module JednaTournaments
  # Agent that runs as a subprocess and communicates via stdin/stdout
  class ProcessAgent < BaseAgent
    def initialize(command, name = nil)
      super(name)
      @command = command
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @wait_thread = nil
    end
    
    def start
      raise AgentError, "Agent already running" if running?
      
      @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(@command)
      @stdin.sync = true
      @stdout.sync = true
    rescue => e
      raise AgentError, "Failed to start agent: #{e.message}"
    end
    
    def stop
      return unless running?
      
      # Try graceful shutdown first
      begin
        notify_game_end('game_cancelled', {})
      rescue
        # Ignore errors during shutdown
      end
      
      # Close pipes
      [@stdin, @stdout, @stderr].each { |io| io.close rescue nil }
      
      # Wait for process to exit
      begin
        Timeout.timeout(1) do
          @wait_thread.join
        end
      rescue Timeout::Error
        # Force kill if it doesn't exit gracefully
        Process.kill('KILL', @wait_thread.pid) rescue nil
      end
      
      @stdin = @stdout = @stderr = @wait_thread = nil
    end
    
    def running?
      return false unless @wait_thread
      @wait_thread.alive?
    end
    
    def request_action(game_state, timeout: nil)
      raise AgentError, "Agent not running" unless running?
      
      timeout ||= JednaTournaments.configuration.timeout
      
      request = {
        type: 'request_action',
        state: game_state
      }
      
      response = nil
      
      Timeout.timeout(timeout) do
        @stdin.puts JSON.generate(request)
        response_line = @stdout.gets
        
        raise AgentError, "Agent closed output" if response_line.nil?
        
        begin
          response = JSON.parse(response_line.strip)
        rescue JSON::ParserError => e
          raise AgentError, "Invalid JSON response from agent: #{response_line}"
        end
      end
      
      response
    rescue Timeout::Error
      raise TimeoutError, "Agent did not respond within #{timeout} seconds"
    end
    
    def notify(message)
      return unless running?
      
      if message.is_a?(String)
        # Parse it to ensure it's valid JSON, then send it
        JSON.parse(message)
        @stdin.puts message
      else
        @stdin.puts JSON.generate(message)
      end
    rescue Errno::EPIPE
      # Agent has closed its input, likely exiting
    rescue => e
      # Log but don't raise - notifications are best effort
      warn "Failed to send notification to agent: #{e.message}"
    end
  end
end