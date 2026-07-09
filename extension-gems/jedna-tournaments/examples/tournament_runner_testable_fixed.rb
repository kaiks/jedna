#!/usr/bin/env ruby
# frozen_string_literal: true

# Fixed Testable Tournament Runner
#
# This version fixes the issues found in tests:
# - Proper agent passing in handle_draw
# - Correct game completion tracking
# - Better error handling for crashed agents
# - Fixed elimination tracking
#
# Usage: ruby tournament_runner_testable_fixed.rb <config.yaml>

require 'bundler/setup'
require 'jedna'
require 'yaml'
require 'forwardable'
require_relative '../lib/jedna_tournaments'

# Manages tournament configuration
class TournamentConfig
  extend Forwardable

  attr_reader :agents, :tournament_type, :games_per_round, :turn_timeout, :game_timeout, :stdout_output, :log_file,
              :results_file, :game_log_file

  def_delegators :@config, :[]

  def initialize(config_file_or_hash)
    @config = case config_file_or_hash
              when String
                YAML.load_file(config_file_or_hash)
              when Hash
                config_file_or_hash
              else
                raise ArgumentError, "Expected String or Hash, got #{config_file_or_hash.class}"
              end

    validate!
    extract_settings
  end

  def validate!
    raise 'No agents configured' unless @config['agents'] && !@config['agents'].empty?
    raise 'At least 2 agents required' if @config['agents'].size < 2

    @config['agents'].each do |name, command|
      raise "Agent #{name} has no command" if command.nil? || command.empty?
    end
  end

  private

  def extract_settings
    @agents = @config['agents']
    @tournament_type = @config['tournament_type'] || 'round-robin'
    @games_per_round = @config['games_per_round'] || 10

    # Output configuration
    @stdout_output = @config.dig('output', 'stdout') != false
    @log_file = @config.dig('output', 'log_file')
    @results_file = @config.dig('output', 'log_results_file')
    @game_log_file = @config.dig('output', 'game_log_file')

    # Timeout configuration
    @turn_timeout = @config.dig('timeouts', 'turn_timeout') || 1.0
    @game_timeout = @config.dig('timeouts', 'game_timeout') || 10.0
    @turn_timeout = nil if @turn_timeout.zero?
    @game_timeout = nil if @game_timeout.zero?
  end
end

# Executes single games with Jedna integration
class GameEngine
  attr_reader :current_game_log, :winner_id

  def initialize(serializer = Jedna::GameStateSerializer.new)
    @serializer = serializer
    @current_game_log = []
    @game_ended = false
    @winner_id = nil
    @turn_timeout = nil
  end

  def play_game(player1_name, player2_name, agent_map, turn_timeout: nil, game_timeout: nil)
    @current_game_log = []
    @game_ended = false
    @winner_id = nil
    @turn_timeout = turn_timeout
    @agent_map = agent_map

    game = setup_game(player1_name, player2_name)
    game.start_game

    wait_for_completion(game_timeout)

    @winner_id
  end

  private

  def setup_game(player1_name, player2_name)
    game = Jedna::Game.new('tournament')

    player1 = Jedna::Player.new(Jedna::SimpleIdentity.new(player1_name))
    player2 = Jedna::Player.new(Jedna::SimpleIdentity.new(player2_name))

    game.add_player(player1)
    game.add_player(player2)

    # Set up event handlers
    game.before_player_turn do |g, current_player|
      handle_turn(g, current_player)
    end

    game.on_game_ended do
      handle_game_end(game)
    end

    game
  end

  def handle_turn(game, player)
    agent = @agent_map[player.identity.id]
    return unless agent

    state = @serializer.serialize_for_current_player(game)

    # Log initial state
    top_card = state[:state][:top_card] || 'start'
    player_name = player.identity.id
    hand_cards = player.hand.map(&:to_s).sort.join(',')

    begin
      action = agent.request_action(state[:state], timeout: @turn_timeout)
      execute_action(game, player, action, top_card, player_name, hand_cards)
    rescue StandardError
      @current_game_log << "#{top_card};#{player_name};#{hand_cards};error"
      game.pick_single unless game.instance_variable_get(:@already_picked)
      game.turn_pass
    end
  end

  def execute_action(game, player, action, top_card, player_name, hand_cards)
    case action['action']
    when 'play'
      handle_play(game, player, action, top_card, player_name, hand_cards)
    when 'draw'
      handle_draw(game, player, top_card, player_name, hand_cards)
    when 'pass'
      @current_game_log << "#{top_card};#{player_name};#{hand_cards};pass"
      game.turn_pass
    else
      raise "Unknown action: #{action['action']}"
    end
  end

  def handle_play(game, player, action, top_card, player_name, hand_cards)
    card = find_card(player.hand, action['card'])
    return unless card

    played_card = action['card']
    played_card += action['wild_color'][0] if action['wild_color']
    @current_game_log << "#{top_card};#{player_name};#{hand_cards};#{played_card}"

    card.set_wild_color(action['wild_color'].to_sym) if action['wild_color']
    game.player_card_play(player, card, action['double_play'] == true)
  end

  def handle_draw(game, player, top_card, player_name, hand_cards)
    @current_game_log << "#{top_card};#{player_name};#{hand_cards};draw"
    game.pick_single

    return unless game.instance_variable_get(:@already_picked)

    # Allow playing drawn card
    agent = @agent_map[player.identity.id]
    return unless agent

    new_state = @serializer.serialize_for_current_player(game)
    hand_cards = player.hand.map(&:to_s).sort.join(',')

    follow_up = agent.request_action(new_state[:state], timeout: @turn_timeout)

    if follow_up['action'] == 'play'
      handle_play(game, player, follow_up, top_card, player_name, hand_cards)
    else
      @current_game_log << "#{top_card};#{player_name};#{hand_cards};pass"
      game.turn_pass
    end
  end

  def find_card(hand, card_string)
    case card_string
    when 'w'
      hand.find { |c| c.figure == 'wild' }
    when 'wd4'
      hand.find { |c| c.figure == 'wild+4' }
    else
      hand.find { |c| c.to_s == card_string }
    end
  end

  def handle_game_end(game)
    winner = game.winner
    @winner_id = winner.identity.id

    @current_game_log << "#{@winner_id} wins"

    # Notify agents
    scores = {}
    game.players.each { |p| scores[p.identity.id] = p.hand.value }

    @agent_map.each_value do |agent|
      agent.notify_game_end(@winner_id, scores)
    rescue StandardError
      # Ignore notification errors
    end

    @game_ended = true
  end

  def wait_for_completion(timeout)
    # Always use a maximum timeout to prevent infinite loops
    actual_timeout = timeout || 30.0
    start = Time.now

    sleep 0.05 while !@game_ended && (Time.now - start) < actual_timeout

    # If game didn't end naturally, we still need to clean up
    return if @game_ended

    @game_ended = true
  end
end

# Manages tournament scheduling
class TournamentScheduler
  attr_reader :matches

  def initialize(agent_names, tournament_type)
    @agent_names = agent_names
    @tournament_type = tournament_type
    @matches = []
  end

  def generate_round_robin_matches
    @matches = []
    @agent_names.combination(2) do |agent1, agent2|
      @matches << { player1: agent1, player2: agent2, type: :round_robin }
    end
    @matches
  end

  def generate_elimination_bracket
    @brackets = []
    remaining = @agent_names.shuffle
    round_num = 0

    while remaining.size > 1
      round_num += 1
      round_matches = []

      remaining.each_slice(2) do |agent1, agent2|
        round_matches << if agent2.nil?
                           # Bye
                           { player1: agent1, player2: nil, type: :bye, round: round_num }
                         else
                           { player1: agent1, player2: agent2, type: :elimination, round: round_num }
                         end
      end

      @brackets << { round: round_num, matches: round_matches }

      # Simulate advancement for bracket generation
      remaining = round_matches.map { |m| m[:player2] ? [m[:player1], m[:player2]].sample : m[:player1] }
    end

    @brackets
  end
end

# Tracks tournament results and statistics
class ResultsTracker
  attr_reader :results, :match_results, :game_logs

  def initialize
    @results = {}
    @match_results = []
    @game_logs = []
  end

  def record_match(player1, player2, wins, winner)
    @match_results << {
      players: [player1, player2],
      wins: wins,
      winner: winner
    }

    # Update overall stats
    total_games = wins.values.sum
    [player1, player2].each do |player|
      @results[player] ||= { wins: 0, losses: 0, games: 0 }
      @results[player][:games] += total_games
      @results[player][:wins] += wins[player]
      @results[player][:losses] += total_games - wins[player]
    end
  end

  def record_game(winner, players, log)
    @game_logs << {
      winner: winner,
      players: players,
      log: log
    }
  end

  def mark_elimination(agent, round)
    @results[agent] ||= { wins: 0, losses: 0, games: 0 }
    @results[agent][:eliminated_round] = round
  end

  def generate_report(tournament_type, duration)
    case tournament_type
    when 'round-robin'
      generate_round_robin_report(duration)
    when 'elimination-bracket'
      generate_elimination_report(duration)
    else
      "Unknown tournament type: #{tournament_type}"
    end
  end

  private

  def generate_round_robin_report(duration)
    output = []
    output << "\n📊 FINAL TOURNAMENT RESULTS"
    output << ('=' * 60)
    output << 'Tournament: round-robin'
    output << "Total duration: #{duration.round(2)} seconds"
    output << ''
    output << 'STANDINGS:'

    sorted_results = @results.sort_by { |_, stats| [-stats[:wins], stats[:games]] }

    sorted_results.each_with_index do |(agent, stats), idx|
      win_rate = stats[:games].positive? ? (stats[:wins].to_f / stats[:games] * 100).round(1) : 0.0
      output << "#{idx + 1}. #{agent}: #{stats[:wins]} wins / #{stats[:games]} games (#{win_rate}%)"
    end

    output.join("\n")
  end

  def generate_elimination_report(duration)
    output = []
    champion = @results.find { |_, stats| stats[:eliminated_round].nil? }&.first

    output << "\n📊 FINAL TOURNAMENT RESULTS"
    output << ('=' * 60)
    output << 'Tournament: elimination-bracket'
    output << "Total duration: #{duration.round(2)} seconds"
    output << ''
    output << "🏆 CHAMPION: #{champion}" if champion

    output.join("\n")
  end
end

# Main tournament orchestrator
class TournamentOrchestrator
  attr_reader :config, :game_engine, :scheduler, :results_tracker

  def initialize(config)
    @config = config.is_a?(TournamentConfig) ? config : TournamentConfig.new(config)
    @game_engine = GameEngine.new
    @scheduler = TournamentScheduler.new(@config.agents.keys, @config.tournament_type)
    @results_tracker = ResultsTracker.new
    @agents = {}
    @log_file = nil
    @game_log_file = nil
  end

  def run
    setup_logging
    log_header

    start_time = Time.now

    case @config.tournament_type
    when 'round-robin'
      run_round_robin
    when 'elimination-bracket'
      run_elimination_bracket
    else
      raise "Unknown tournament type: #{@config.tournament_type}"
    end

    duration = Time.now - start_time

    finalize_results(duration)
  ensure
    cleanup
  end

  private

  def setup_logging
    @log_file = File.open(@config.log_file, 'w') if @config.log_file

    return unless @config.game_log_file

    require 'fileutils'
    FileUtils.mkdir_p(File.dirname(@config.game_log_file))
    @game_log_file = File.open(@config.game_log_file, 'w')
  end

  def log_header
    log_output '🏆 Jedna Tournament', :header
    log_output '=' * 60, :header
    log_output "Tournament Type: #{@config.tournament_type}"
    log_output "Games per round: #{@config.games_per_round}"
    log_output "Agents: #{@config.agents.keys.join(', ')}"
    log_output '=' * 60, :header
    log_output ''
  end

  def run_round_robin
    matches = @scheduler.generate_round_robin_matches
    total = matches.size

    matches.each_with_index do |match, idx|
      log_output "Match #{idx + 1}/#{total}: #{match[:player1]} vs #{match[:player2]}"

      wins = { match[:player1] => 0, match[:player2] => 0 }

      @config.games_per_round.times do |game_num|
        # Alternate who goes first
        winner = if game_num.even?
                   play_match_game(match[:player1], match[:player2])
                 else
                   play_match_game(match[:player2], match[:player1])
                 end

        wins[winner] += 1 if winner
        print '.' if @config.stdout_output
      end

      log_output ' Complete!' if @config.stdout_output

      match_winner = wins.max_by { |_, v| v }[0]
      @results_tracker.record_match(match[:player1], match[:player2], wins, match_winner)
    end
  end

  def run_elimination_bracket
    brackets = @scheduler.generate_elimination_bracket
    remaining_agents = @config.agents.keys.shuffle

    brackets.each do |bracket|
      log_output "\n📊 Round #{bracket[:round]}", :header
      log_output '-' * 40, :header

      next_round = []

      # Process matches in pairs to match the actual remaining agents
      remaining_agents.each_slice(2).with_index do |(player1, player2), _match_idx|
        if player2.nil?
          log_output "#{player1} gets a bye"
          next_round << player1
          next
        end

        winner = run_elimination_match(player1, player2, bracket[:round])
        next_round << winner

        # Mark the loser as eliminated
        loser = [player1, player2].find { |p| p != winner }
        @results_tracker.mark_elimination(loser, bracket[:round])
      end

      remaining_agents = next_round
    end

    log_output "\n🏆 Tournament Champion: #{remaining_agents.first}!", :header if remaining_agents.any?
  end

  def run_elimination_match(player1, player2, _round_num)
    log_output "Match: #{player1} vs #{player2}"

    wins = { player1 => 0, player2 => 0 }

    @config.games_per_round.times do |game_num|
      winner = if game_num.even?
                 play_match_game(player1, player2)
               else
                 play_match_game(player2, player1)
               end

      wins[winner] += 1 if winner
      print '.' if @config.stdout_output
    end

    log_output ' Complete!' if @config.stdout_output

    match_winner = wins.max_by { |_, v| v }[0]

    @results_tracker.record_match(player1, player2, wins, match_winner)

    log_output "  Winner: #{match_winner} (#{wins[match_winner]}-#{wins.values.min})"

    match_winner
  end

  def play_match_game(player1_name, player2_name)
    # Create agents if not already created
    @agents[player1_name] ||= create_agent(player1_name)
    @agents[player2_name] ||= create_agent(player2_name)

    agent1 = @agents[player1_name]
    agent2 = @agents[player2_name]

    # Check if agents are running
    unless agent1.running? && agent2.running?
      # Try to restart dead agents
      agent1.start unless agent1.running?
      agent2.start unless agent2.running?

      # If still not running, return nil
      return nil unless agent1.running? && agent2.running?
    end

    agent_map = {
      player1_name => agent1,
      player2_name => agent2
    }

    winner_id = @game_engine.play_game(
      player1_name,
      player2_name,
      agent_map,
      turn_timeout: @config.turn_timeout,
      game_timeout: @config.game_timeout
    )

    # Record game log
    if winner_id
      @results_tracker.record_game(winner_id, [player1_name, player2_name], @game_engine.current_game_log)
      save_game_log(player1_name, player2_name, winner_id)
    end

    winner_id
  rescue StandardError => e
    log_output "Error in game: #{e.message}"
    nil
  end

  def create_agent(name)
    agent = JednaTournaments::ProcessAgent.new(@config.agents[name], name)
    agent.start
    agent
  end

  def save_game_log(player1, player2, winner)
    return unless @game_log_file

    game_num = @results_tracker.game_logs.size
    @game_log_file.puts "Game #{game_num}: #{player1} vs #{player2} - Winner: #{winner}"
    @game_engine.current_game_log.each { |line| @game_log_file.puts line }
    @game_log_file.puts
    @game_log_file.flush
  end

  def finalize_results(duration)
    report = @results_tracker.generate_report(@config.tournament_type, duration)
    log_output report, :results

    return unless @config.results_file

    File.write(@config.results_file, report)
    log_output "Results saved to: #{@config.results_file}"
  end

  def log_output(message, type = :normal)
    return unless message

    @log_file&.puts(message)
    @log_file&.flush

    return unless @config.stdout_output || type == :results

    puts message
  end

  def cleanup
    @agents.each_value do |agent|
      agent.stop
    rescue StandardError
      nil
    end

    @log_file&.close
    @game_log_file&.close
  end
end

# Run if called directly
if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    puts "Usage: #{$PROGRAM_NAME} <config.yaml>"
    exit 1
  end

  orchestrator = TournamentOrchestrator.new(ARGV[0])
  orchestrator.run
end
