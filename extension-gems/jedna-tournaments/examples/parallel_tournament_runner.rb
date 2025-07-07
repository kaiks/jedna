#!/usr/bin/env ruby
# frozen_string_literal: true

# Parallel Tournament Runner - Execute tournaments across multiple processes
#
# This runner splits tournament games across multiple processes for faster
# execution, then automatically merges the results with statistical analysis.
#
# Features:
# - Automatic work distribution across N processes
# - Result merging with confidence intervals
# - Process-isolated execution for stability
# - Configurable via YAML with 'parallel' section
#
# Usage: ruby parallel_tournament_runner.rb <config.yaml>
# Config should include:
#   parallel:
#     processes: 4
#     output_dir: results/
#     merge_results: true

require 'yaml'
require 'json'
require 'fileutils'
require 'tempfile'

class ParallelTournamentRunner
  def initialize(config_file)
    @config = YAML.load_file(config_file)
    @processes = @config.dig('parallel', 'processes') || 1
    @base_output_dir = @config.dig('parallel', 'output_dir') || 'parallel_results'
    @merge_results = @config.dig('parallel', 'merge_results') != false
    
    # Ensure output directory exists
    FileUtils.mkdir_p(@base_output_dir)
  end
  
  def run
    if @processes <= 1
      # Single process - just run normally
      system("ruby tournament_runner.rb #{ARGV[0]}")
      return
    end
    
    puts "Starting parallel tournament with #{@processes} processes..."
    puts "Total games: #{@config['games_per_round']}"
    
    # Calculate games per process
    total_games = @config['games_per_round']
    games_per_process = total_games / @processes
    remainder = total_games % @processes
    
    # Create temporary configs for each process
    process_configs = []
    process_pids = []
    
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
      process_config['output']['stdout'] = false  # Silence individual processes
      process_config['output']['log_file'] = File.join(process_dir, 'tournament.log')
      process_config['output']['log_results_file'] = File.join(process_dir, 'results.txt')
      process_config['output']['game_log_file'] = File.join(process_dir, 'games.log')
      
      # Write temporary config
      config_file = File.join(process_dir, 'config.yaml')
      File.write(config_file, YAML.dump(process_config))
      process_configs << config_file
      
      puts "Process #{i}: #{games} games"
    end
    
    # Start all processes
    start_time = Time.now
    
    process_configs.each_with_index do |config_file, i|
      pid = fork do
        # Child process - run tournament
        exec("ruby tournament_runner.rb #{config_file}")
      end
      
      if pid
        process_pids << pid
        puts "Started process #{i} (PID: #{pid})"
      end
    end
    
    # Wait for all processes to complete
    puts "\nWaiting for all processes to complete..."
    
    process_pids.each_with_index do |pid, i|
      Process.wait(pid)
      status = $?
      if status.success?
        puts "Process #{i} completed successfully"
      else
        puts "Process #{i} failed with status #{status.exitstatus}"
      end
    end
    
    duration = Time.now - start_time
    puts "\nAll processes completed in #{duration.round(2)} seconds"
    
    # Merge results if requested
    if @merge_results
      merge_all_results
    else
      puts "\nResults saved in: #{@base_output_dir}/"
      puts "Run with merge_results: true to combine results"
    end
  end
  
  private
  
  def merge_all_results
    puts "\nMerging results..."
    
    # Collect all results
    total_games = 0
    total_wins = Hash.new(0)
    all_game_logs = []
    all_match_results = []
    
    @processes.times do |i|
      process_dir = File.join(@base_output_dir, "process_#{i}")
      
      # Read results file
      results_file = File.join(process_dir, 'results.txt')
      if File.exist?(results_file)
        parse_results_file(results_file, total_wins)
      end
      
      # Read game logs
      game_log_file = File.join(process_dir, 'games.log')
      if File.exist?(game_log_file)
        File.readlines(game_log_file).each do |line|
          all_game_logs << line.strip
          total_games += 1
        end
      end
    end
    
    # Write merged results
    write_merged_results(total_games, total_wins, all_game_logs)
  end
  
  def parse_results_file(file, total_wins)
    content = File.read(file)
    
    # Parse match results
    if content =~ /Match: (\w+) vs (\w+)/
      agent1, agent2 = $1, $2
      
      # Extract wins
      if content =~ /#{agent1}: (\d+) wins/
        total_wins[agent1] += $1.to_i
      end
      if content =~ /#{agent2}: (\d+) wins/
        total_wins[agent2] += $1.to_i
      end
    end
  end
  
  def write_merged_results(total_games, total_wins, all_game_logs)
    # Create merged output directory
    merged_dir = File.join(@base_output_dir, 'merged')
    FileUtils.mkdir_p(merged_dir)
    
    # Write merged game log
    if all_game_logs.any?
      File.write(File.join(merged_dir, 'all_games.log'), all_game_logs.join("\n"))
    end
    
    # Write summary results
    File.open(File.join(merged_dir, 'tournament_summary.txt'), 'w') do |f|
      f.puts "Parallel Tournament Results"
      f.puts "=" * 50
      f.puts "Total games played: #{total_games}"
      f.puts "Processes used: #{@processes}"
      f.puts
      f.puts "Agent Results:"
      
      total_wins.each do |agent, wins|
        win_rate = (wins.to_f / total_games * 100).round(1)
        f.puts "#{agent}: #{wins} wins (#{win_rate}%)"
      end
      
      # Calculate confidence intervals
      if total_games > 0
        f.puts
        f.puts "Statistical Analysis:"
        total_wins.each do |agent, wins|
          lower, upper = wilson_confidence_interval(wins, total_games)
          f.puts "#{agent} 95% CI: [#{(lower * 100).round(1)}%, #{(upper * 100).round(1)}%]"
        end
      end
    end
    
    puts "\nMerged results saved to: #{File.join(merged_dir, 'tournament_summary.txt')}"
    
    # Display summary
    puts "\nTournament Summary:"
    puts "=" * 50
    puts "Total games: #{total_games}"
    total_wins.each do |agent, wins|
      win_rate = (wins.to_f / total_games * 100).round(1)
      puts "#{agent}: #{wins} wins (#{win_rate}%)"
    end
  end
  
  def wilson_confidence_interval(wins, total, confidence = 0.95)
    return [0, 0] if total == 0
    
    z = 1.96  # 95% confidence
    p_hat = wins.to_f / total
    
    denominator = 1 + z**2 / total
    center = (p_hat + z**2 / (2 * total)) / denominator
    margin = z * Math.sqrt(p_hat * (1 - p_hat) / total + z**2 / (4 * total**2)) / denominator
    
    [[center - margin, 0].max, [center + margin, 1].min]
  end
end

# Run if executed directly
if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: ruby parallel_tournament_runner.rb <config_file>"
    exit 1
  end
  
  runner = ParallelTournamentRunner.new(ARGV[0])
  runner.run
end