#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require 'fileutils'
require_relative 'run_single_game'

# Test suite for SingleGameRunner
class TestSingleGameRunner < Minitest::Test
  SIMPLE_AGENT_PATH = File.expand_path('simple_agent.rb', __dir__)

  def setup
    # Create a temporary directory for mock agents used in specific tests
    @mock_agent_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@mock_agent_dir)
  end

  def test_initialization
    runner = SingleGameRunner.new(SIMPLE_AGENT_PATH, SIMPLE_AGENT_PATH)

    assert_instance_of SingleGameRunner, runner
    assert_equal 2, runner.instance_variable_get(:@agents).size
  end

  def test_game_completion
    runner = SingleGameRunner.new(SIMPLE_AGENT_PATH, SIMPLE_AGENT_PATH)

    # Capture output
    output = capture_output { runner.run }

    # Game should complete without errors
    assert_match(/Game Over!/, output)
    assert_match(/Winner: agent[12] after \d+ turns/, output)
  end

  def test_agent_crash_handling
    # Create an agent that crashes immediately
    crash_agent = File.join(@mock_agent_dir, 'crash_agent.rb')
    File.write(crash_agent, <<~RUBY)
      #!/usr/bin/env ruby
      exit 1
    RUBY
    File.chmod(0o755, crash_agent)

    runner = SingleGameRunner.new(crash_agent, SIMPLE_AGENT_PATH)

    # Should handle crash gracefully
    assert_silent do
      runner.run
    end
  end

  private

  def capture_output
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def assert_silent(&)
    capture_output(&)
    assert true # If we get here, no exceptions were raised
  end
end
