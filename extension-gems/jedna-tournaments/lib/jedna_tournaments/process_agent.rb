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
      @stderr_thread = nil
      @stderr_tail = []
    end
    
    def start
      raise AgentError, "Agent already running" if running?

      cleanup_process_resources if @wait_thread
      @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(@command)
      @stdin.sync = true
      @stdout.sync = true
      start_stderr_drain
    rescue => e
      cleanup_process_resources
      raise AgentError, "Failed to start agent: #{e.message}"
    end
    
    def stop(graceful: true)
      return cleanup_process_resources unless @wait_thread

      notify_game_end('game_cancelled', {}) if graceful && running?
      @stdin&.close unless @stdin&.closed?

      wait_for_exit(graceful ? 1 : 0.1)
    ensure
      cleanup_process_resources
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
      stop(graceful: false)
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

    private

    def start_stderr_drain
      @stderr_thread = Thread.new do
        @stderr.each_line do |line|
          @stderr_tail << line
          @stderr_tail.shift while @stderr_tail.size > 100
        end
      rescue IOError
        nil
      end
      @stderr_thread.report_on_exception = false
    end

    def wait_for_exit(timeout)
      return unless @wait_thread&.alive?

      @wait_thread.join(timeout)
      return unless @wait_thread.alive?

      Process.kill('KILL', @wait_thread.pid)
      @wait_thread.join
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def cleanup_process_resources
      [@stdin, @stdout, @stderr].compact.each do |io|
        io.close unless io.closed?
      rescue IOError
        nil
      end
      @stderr_thread&.join(0.1)
      @stdin = @stdout = @stderr = @wait_thread = @stderr_thread = nil
    end
  end
end
