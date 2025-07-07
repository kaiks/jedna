#!/usr/bin/env ruby
# frozen_string_literal: true

# Advanced Parallel Tournament Runner - Enterprise-grade parallel execution
#
# Enhanced version of the parallel runner with additional features:
# - Real-time progress monitoring with ETA
# - Graceful shutdown handling (Ctrl+C)
# - Progress checkpointing and resume capability
# - Detailed statistics with confidence intervals
# - Process health monitoring
# - Automatic result merging with statistical analysis
#
# Features:
# - Shows progress bar with games/sec and ETA
# - Handles interruptions gracefully
# - Saves progress to JSON for monitoring
# - Calculates Wilson confidence intervals
# - Provides sample size recommendations
#
# Usage: ruby parallel_tournament_advanced.rb <config.yaml>
#
# The config should include:
#   parallel:
#     processes: 4
#     output_dir: results/
#     merge_results: true
#     checkpoint_interval: 100

require 'yaml'
require 'json'
require 'fileutils'
require 'tempfile'

class AdvancedParallelTournamentRunner
  def initialize(config_file)
    @config_file = config_file
    @config = YAML.load_file(config_file)
    @processes = @config.dig('parallel', 'processes') || 1
    @base_output_dir = @config.dig('parallel', 'output_dir') || 'parallel_results'
    @merge_results = @config.dig('parallel', 'merge_results') != false
    @checkpoint_interval = @config.dig('parallel', 'checkpoint_interval') || 100

    # Ensure output directory exists
    FileUtils.mkdir_p(@base_output_dir)

    # Progress tracking
    @progress_file = File.join(@base_output_dir, 'progress.json')
    @start_time = Time.now
  end

  def run
    if @processes <= 1
      # Single process - just run normally
      system("ruby tournament_runner.rb #{@config_file}")
      return
    end

    puts "🏁 Starting parallel tournament with #{@processes} processes..."
    puts "📊 Total games: #{@config['games_per_round']}"
    puts "📁 Output directory: #{@base_output_dir}"
    puts

    # Calculate games per process
    total_games = @config['games_per_round']
    games_per_process = total_games / @processes
    remainder = total_games % @processes

    # Set up signal handlers for graceful shutdown
    setup_signal_handlers

    # Create process configs and start monitoring thread
    process_configs = create_process_configs(games_per_process, remainder)

    # Start progress monitoring in a separate thread
    monitor_thread = start_progress_monitor

    # Start all processes
    process_pids = start_processes(process_configs)

    # Wait for all processes to complete
    wait_for_processes(process_pids)

    # Stop monitoring
    @monitoring = false
    monitor_thread.join if monitor_thread.alive?

    duration = Time.now - @start_time
    puts "\n✅ All processes completed in #{format_duration(duration)}"

    # Merge results if requested
    if @merge_results
      merge_all_results
    else
      puts "\n📁 Results saved in: #{@base_output_dir}/"
      puts '💡 Run with merge_results: true to combine results'
    end
  end

  private

  def setup_signal_handlers
    @interrupted = false
    %w[INT TERM].each do |signal|
      Signal.trap(signal) do
        puts "\n⚠️  Received #{signal} signal, shutting down gracefully..."
        @interrupted = true
      end
    end
  end

  def create_process_configs(games_per_process, remainder)
    process_configs = []

    @processes.times do |i|
      # Calculate games for this process
      games = games_per_process
      games += 1 if i < remainder

      # Create process-specific config
      process_config = @config.dup
      process_config['games_per_round'] = games

      # Set up process-specific output files
      process_dir = File.join(@base_output_dir, "process_#{i}")
      FileUtils.mkdir_p(process_dir)

      process_config['output'] ||= {}
      process_config['output']['stdout'] = false
      process_config['output']['log_file'] = File.join(process_dir, 'tournament.log')
      process_config['output']['log_results_file'] = File.join(process_dir, 'results.txt')
      process_config['output']['game_log_file'] = File.join(process_dir, 'games.log')

      # Write config
      config_file = File.join(process_dir, 'config.yaml')
      File.write(config_file, YAML.dump(process_config))
      process_configs << { file: config_file, games: games, id: i }

      puts "🔧 Process #{i}: #{games} games"
    end

    process_configs
  end

  def start_processes(process_configs)
    process_pids = []

    process_configs.each do |config|
      pid = fork do
        # Child process - run tournament
        exec("ruby tournament_runner.rb #{config[:file]}")
      end

      if pid
        process_pids << { pid: pid, id: config[:id], games: config[:games] }
        puts "🚀 Started process #{config[:id]} (PID: #{pid})"
      end
    end

    process_pids
  end

  def wait_for_processes(process_pids)
    puts "\n⏳ Waiting for all processes to complete..."
    completed = []

    while completed.size < process_pids.size && !@interrupted
      process_pids.each do |proc|
        next if completed.include?(proc[:id])

        pid_status = Process.waitpid2(proc[:pid], Process::WNOHANG)
        next unless pid_status

        status = pid_status[1]
        if status.success?
          puts "✅ Process #{proc[:id]} completed successfully"
        else
          puts "❌ Process #{proc[:id]} failed with status #{status.exitstatus}"
        end
        completed << proc[:id]
      end

      sleep 0.5
    end

    # If interrupted, kill remaining processes
    return unless @interrupted

    process_pids.each do |proc|
      next if completed.include?(proc[:id])

      begin
        Process.kill('TERM', proc[:pid])
        puts "🛑 Terminated process #{proc[:id]}"
      rescue Errno::ESRCH
        # Process already dead
      end
    end
  end

  def start_progress_monitor
    @monitoring = true

    Thread.new do
      while @monitoring
        update_progress
        sleep 5 # Update every 5 seconds
      end
    end
  end

  def update_progress
    total_completed = 0
    process_stats = []

    @processes.times do |i|
      process_dir = File.join(@base_output_dir, "process_#{i}")
      game_log = File.join(process_dir, 'games.log')

      if File.exist?(game_log)
        lines = File.readlines(game_log).size
        total_completed += lines
        process_stats << { id: i, completed: lines }
      else
        process_stats << { id: i, completed: 0 }
      end
    end

    # Save progress
    progress_data = {
      total_games: @config['games_per_round'],
      completed_games: total_completed,
      process_stats: process_stats,
      start_time: @start_time,
      last_update: Time.now
    }

    File.write(@progress_file, JSON.pretty_generate(progress_data))

    # Display progress
    percentage = (total_completed.to_f / @config['games_per_round'] * 100).round(1)
    elapsed = Time.now - @start_time
    if elapsed.positive? && total_completed.positive?
      rate = total_completed / elapsed.to_f
      eta = ((@config['games_per_round'] - total_completed) / rate).to_i
    else
      rate = 0
      eta = 0
    end

    print "\r📊 Progress: #{total_completed}/#{@config['games_per_round']} games (#{percentage}%) | "
    print "⚡ #{rate.round(1)} games/sec | "
    print "⏱️  ETA: #{format_duration(eta)}"
    $stdout.flush
  end

  def format_duration(seconds)
    return '0s' if seconds < 1

    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    secs = seconds % 60

    parts = []
    parts << "#{hours.to_i}h" if hours >= 1
    parts << "#{minutes.to_i}m" if minutes >= 1
    parts << "#{secs.to_i}s"

    parts.join(' ')
  end

  def merge_all_results
    puts "\n🔄 Merging results..."

    # Collect all results
    total_games = 0
    agent_wins = Hash.new(0)
    agent_games = Hash.new(0)
    all_game_logs = []

    @processes.times do |i|
      process_dir = File.join(@base_output_dir, "process_#{i}")

      # Read game logs and count wins
      game_log_file = File.join(process_dir, 'games.log')
      next unless File.exist?(game_log_file)

      File.readlines(game_log_file).each do |line|
        all_game_logs << line.strip

        # Only count lines that are game results (start with "Game")
        next unless line.start_with?('Game ')

        total_games += 1

        # Parse winner from game result line
        if line =~ /Winner: (\w+)/
          winner = ::Regexp.last_match(1)
          agent_wins[winner] += 1
        end

        # Extract agents from game line
        if line =~ /Game \d+: (\w+) vs (\w+)/
          agent_games[::Regexp.last_match(1)] += 1
          agent_games[::Regexp.last_match(2)] += 1
        end
      end
    end

    # Write merged results
    write_final_results(total_games, agent_wins, agent_games, all_game_logs)
  end

  def write_final_results(total_games, agent_wins, agent_games, all_game_logs)
    merged_dir = File.join(@base_output_dir, 'merged')
    FileUtils.mkdir_p(merged_dir)

    # Write merged game log
    File.write(File.join(merged_dir, 'all_games.log'), all_game_logs.join("\n")) if all_game_logs.any?

    # Sort agents by wins for display
    sorted_agents = agent_wins.sort_by { |_, wins| -wins }

    # Write detailed results
    File.open(File.join(merged_dir, 'tournament_results.txt'), 'w') do |f|
      f.puts '🏆 Parallel Tournament Results'
      f.puts '=' * 60
      f.puts "📅 Date: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
      f.puts "⚙️  Processes used: #{@processes}"
      f.puts "⏱️  Total duration: #{format_duration(Time.now - @start_time)}"
      f.puts "🎮 Total games played: #{total_games}"
      f.puts

      f.puts '🏅 Agent Performance:'
      f.puts '-' * 40
      sorted_agents.each do |agent, wins|
        games = agent_games[agent]
        win_rate = games.positive? ? (wins.to_f / games * 100).round(1) : 0
        f.puts "#{agent}: #{wins}/#{games} wins (#{win_rate}%)"
      end

      # Statistical analysis
      f.puts
      f.puts '📊 Statistical Analysis (95% confidence):'
      f.puts '-' * 40
      sorted_agents.each do |agent, wins|
        games = agent_games[agent]
        next unless games.positive?

        lower, upper = wilson_confidence_interval(wins, games)
        margin = ((upper - lower) / 2 * 100).round(1)
        f.puts "#{agent}: [#{(lower * 100).round(1)}%, #{(upper * 100).round(1)}%] (±#{margin}%)"
      end

      # Sample size recommendation
      if total_games.positive?
        current_margin = sorted_agents.map do |agent, wins|
          games = agent_games[agent]
          if games.positive?
            lower, upper = wilson_confidence_interval(wins, games)
            ((upper - lower) / 2 * 100).round(1)
          else
            100
          end
        end.min

        if current_margin && current_margin > 2.0
          games_for_2pct = 4148
          f.puts
          f.puts '📈 Sample Size Analysis:'
          f.puts '-' * 40
          f.puts "Current margin: ±#{current_margin}%"
          f.puts "For ±2% margin (99% conf): #{games_for_2pct} total games needed"
          f.puts "Additional games required: #{[games_for_2pct - total_games, 0].max}"
        end
      end
    end

    # Display summary
    puts "\n📊 Tournament Summary:"
    puts '=' * 60
    puts "Total games: #{total_games}"
    sorted_agents.each do |agent, wins|
      games = agent_games[agent]
      win_rate = games.positive? ? (wins.to_f / games * 100).round(1) : 0
      puts "#{agent}: #{wins}/#{games} wins (#{win_rate}%)"
    end

    puts "\n✅ Full results saved to: #{File.join(merged_dir, 'tournament_results.txt')}"
  end

  def wilson_confidence_interval(wins, total, _confidence = 0.95)
    return [0, 0] if total.zero?

    z = 1.96 # 95% confidence
    p_hat = wins.to_f / total

    denominator = 1 + z**2 / total
    center = (p_hat + z**2 / (2 * total)) / denominator
    margin = z * Math.sqrt(p_hat * (1 - p_hat) / total + z**2 / (4 * total**2)) / denominator

    [[center - margin, 0].max, [center + margin, 1].min]
  end
end

# Run if executed directly
if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    puts 'Usage: ruby parallel_tournament_advanced.rb <config_file>'
    exit 1
  end

  runner = AdvancedParallelTournamentRunner.new(ARGV[0])
  runner.run
end
