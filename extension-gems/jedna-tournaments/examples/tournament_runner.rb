#!/usr/bin/env ruby
# frozen_string_literal: true

# Tournament Runner - Main tournament engine for Jedna card game
#
# Supports two tournament formats:
# - Round-robin: All agents play against each other
# - Elimination bracket: Single-elimination tournament
#
# Features:
# - Configurable via YAML files
# - Game logging and analysis
# - Timeout handling for stuck agents
# - Statistical result reporting
# - Automatic game state serialization
#
# Usage: ruby tournament_runner.rb <config.yaml>
# See tournament_config.yaml for configuration options

require 'bundler/setup'
require 'jedna'
require 'yaml'
require_relative '../lib/jedna_tournaments'
require 'debug'

class ConfiguredTournamentRunner
  def initialize(config_file)
    @config = YAML.load_file(config_file)
    validate_config!

    @agents = @config['agents']
    @tournament_type = @config['tournament_type'] || 'round-robin'
    @games_per_round = @config['games_per_round'] || 10
    @stdout_output = @config.dig('output', 'stdout') != false
    @log_file = @config.dig('output', 'log_file')
    @results_file = @config.dig('output', 'log_results_file')
    @game_log_file = @config.dig('output', 'game_log_file')

    # Timeout configuration (0 or nil means no timeout)
    @turn_timeout = @config.dig('timeouts', 'turn_timeout') || 1.0
    @game_timeout = @config.dig('timeouts', 'game_timeout') || 10.0
    @turn_timeout = nil if @turn_timeout == 0
    @game_timeout = nil if @game_timeout == 0

    @serializer = Jedna::GameStateSerializer.new
    @results = {}
    @match_results = []
    @game_logs = []
    @current_game_log = []

    # Set up logging
    @log = File.open(@log_file, 'w') if @log_file

    # Set up game log file
    return unless @game_log_file

    # Ensure directory exists
    require 'fileutils'
    FileUtils.mkdir_p(File.dirname(@game_log_file))
    @game_log = File.open(@game_log_file, 'w')
  end

  def run
    log_output '🏆 Jedna Tournament', :header
    log_output '=' * 60, :header
    log_output "Tournament Type: #{@tournament_type}"
    log_output "Games per round: #{@games_per_round}"
    log_output "Agents: #{@agents.keys.join(', ')}"
    log_output "Turn timeout: #{@turn_timeout ? "#{@turn_timeout}s" : 'none'}"
    log_output "Game timeout: #{@game_timeout ? "#{@game_timeout}s" : 'none'}"
    log_output '=' * 60, :header
    log_output ''

    start_time = Time.now

    case @tournament_type
    when 'round-robin'
      run_round_robin
    when 'elimination-bracket'
      run_elimination_bracket
    else
      raise "Unknown tournament type: #{@tournament_type}"
    end

    duration = Time.now - start_time

    # Output final results
    final_results = generate_final_results(duration)
    log_output final_results, :results

    # Save results to file if specified
    if @results_file
      File.write(@results_file, final_results)
      log_output "Results saved to: #{@results_file}"
    end

    # Save game logs for analysis
    save_game_logs

    # Analyze some lost games
    analyze_lost_games
  ensure
    @log&.close
    @game_log&.close
  end

  private

  def validate_config!
    raise 'No agents configured' unless @config['agents'] && !@config['agents'].empty?
    raise 'At least 2 agents required' if @config['agents'].size < 2

    @config['agents'].each do |name, command|
      raise "Agent #{name} has no command" if command.nil? || command.empty?
    end
  end

  def log_output(message, type = :normal)
    return unless message

    # Always log to file if configured
    @log&.puts(message)
    @log&.flush

    # Log to stdout based on type and configuration
    return unless @stdout_output || type == :results

    puts message
  end

  def run_round_robin
    agent_names = @agents.keys
    total_matches = agent_names.combination(2).count
    match_num = 0

    agent_names.combination(2) do |agent1_name, agent2_name|
      match_num += 1
      log_output "Match #{match_num}/#{total_matches}: #{agent1_name} vs #{agent2_name}"

      wins = { agent1_name => 0, agent2_name => 0 }

      @games_per_round.times do |game_num|
        # Alternate who goes first
        winner = if game_num.even?
                   play_game(agent1_name, agent2_name)
                 else
                   play_game(agent2_name, agent1_name)
                 end

        wins[winner] += 1 if winner
        print '.' if @stdout_output
      end

      log_output ' Complete!' if @stdout_output

      # Record match result
      match_winner = wins.max_by { |_, v| v }[0]
      @match_results << {
        players: [agent1_name, agent2_name],
        wins: wins,
        winner: match_winner
      }

      # Update overall stats
      wins.each do |agent, win_count|
        @results[agent] ||= { wins: 0, losses: 0, games: 0 }
        @results[agent][:games] += @games_per_round
        @results[agent][:wins] += win_count
        @results[agent][:losses] += @games_per_round - win_count
      end
    end
  end

  def run_elimination_bracket
    remaining_agents = @agents.keys.shuffle
    round_num = 0

    while remaining_agents.size > 1
      round_num += 1
      log_output "\n📊 Round #{round_num}", :header
      log_output '-' * 40, :header

      next_round = []

      # Pair up agents
      remaining_agents.each_slice(2) do |agent1_name, agent2_name|
        if agent2_name.nil?
          # Bye - agent advances automatically
          log_output "#{agent1_name} gets a bye"
          next_round << agent1_name
          next
        end

        log_output "Match: #{agent1_name} vs #{agent2_name}"

        wins = { agent1_name => 0, agent2_name => 0 }

        @games_per_round.times do |game_num|
          winner = if game_num.even?
                     play_game(agent1_name, agent2_name)
                   else
                     play_game(agent2_name, agent1_name)
                   end

          wins[winner] += 1 if winner
          print '.' if @stdout_output
        end

        log_output ' Complete!' if @stdout_output

        # Determine match winner
        match_winner = wins.max_by { |_, v| v }[0]
        log_output "  Winner: #{match_winner} (#{wins[match_winner]}-#{wins.values.min})"

        next_round << match_winner

        # Record results
        @match_results << {
          round: round_num,
          players: [agent1_name, agent2_name],
          wins: wins,
          winner: match_winner
        }

        # Update stats
        wins.each do |agent, win_count|
          @results[agent] ||= { wins: 0, losses: 0, games: 0, eliminated_round: nil }
          @results[agent][:games] += @games_per_round
          @results[agent][:wins] += win_count
          @results[agent][:losses] += @games_per_round - win_count
        end

        # Mark elimination
        loser = [agent1_name, agent2_name].find { |a| a != match_winner }
        @results[loser][:eliminated_round] = round_num
      end

      remaining_agents = next_round
    end

    log_output "\n🏆 Tournament Champion: #{remaining_agents.first}!", :header
  end

  def play_game(first_agent_name, second_agent_name)
    agent1 = JednaTournaments::ProcessAgent.new(@agents[first_agent_name])
    agent2 = JednaTournaments::ProcessAgent.new(@agents[second_agent_name])

    # Reset game log for this game
    @current_game_log = []

    begin
      agent1.start
      agent2.start

      game = Jedna::Game.new('tournament')

      player1 = Jedna::Player.new(Jedna::SimpleIdentity.new(first_agent_name))
      player2 = Jedna::Player.new(Jedna::SimpleIdentity.new(second_agent_name))

      game.add_player(player1)
      game.add_player(player2)

      player_agent_map = {
        first_agent_name => agent1,
        second_agent_name => agent2
      }

      @player_names = {
        first_agent_name => first_agent_name,
        second_agent_name => second_agent_name
      }

      winner_id = nil

      game.before_player_turn do |g, current_player|
        handle_turn(g, current_player, player_agent_map)
      end

      game_ended = false

      game.on_game_ended do
        winner = game.players[0]
        winner_id = winner.identity.id

        # Add winner to game log
        @current_game_log << "#{winner_id} wins"

        # Write to game log file if configured
        if @game_log
          @game_log.puts "Game #{@game_logs.size + 1}: #{first_agent_name} vs #{second_agent_name} - Winner: #{winner_id}"
          @current_game_log.each { |line| @game_log.puts line }
          @game_log.puts
          @game_log.flush
        end

        @game_logs << {
          winner: winner_id,
          players: [first_agent_name, second_agent_name],
          log: @current_game_log.dup
        }

        # Notify agents
        scores = {}
        game.players.each { |p| scores[p.identity.id] = p.hand.value }
        player_agent_map.each do |_, agent|
          agent.notify_game_end(winner_id, scores)
        rescue StandardError
          nil
        end

        # Mark game as ended
        game_ended = true
      end

      game.start_game

      # Wait for game completion
      if @game_timeout
        start = Time.now
        sleep 0.05 while !game_ended && (Time.now - start) < @game_timeout

        log_output "Game timeout after #{@game_timeout}s" unless game_ended
      else
        # No timeout - wait until game ends
        sleep 0.05 until game_ended
      end

      winner_id
    rescue StandardError => e
      log_output "Error in game: #{e.message}"
      nil
    ensure
      begin
        agent1.stop
      rescue StandardError
        nil
      end
      begin
        agent2.stop
      rescue StandardError
        nil
      end
    end
  end

  def handle_turn(game, player, agent_map)
    agent = agent_map[player.identity.id]
    return unless agent

    state = @serializer.serialize_for_current_player(game)

    # Log game state
    top_card = state[:state][:top_card] || 'start'
    player_name = player.identity.id
    hand_cards = player.hand.map(&:to_s).sort.join(',')

    begin
      action = agent.request_action(state[:state], timeout: @turn_timeout)

      case action['action']
      when 'play'
        card = find_card(player.hand, action['card'])
        if card
          # Log the play
          played_card = action['card']
          played_card += action['wild_color'][0] if action['wild_color']
          @current_game_log << "#{top_card};#{player_name};#{hand_cards};#{played_card}"

          card.set_wild_color(action['wild_color'].to_sym) if action['wild_color']
          game.player_card_play(player, card)
        end
      when 'draw'
        @current_game_log << "#{top_card};#{player_name};#{hand_cards};draw"
        game.pick_single
        if game.instance_variable_get(:@already_picked)
          new_state = @serializer.serialize_for_current_player(game)
          # Update hand for potential play after draw
          hand_cards = player.hand.map(&:to_s).sort.join(',')
          follow_up = agent.request_action(new_state[:state], timeout: @turn_timeout)

          case follow_up['action']
          when 'play'
            card = find_card(player.hand, follow_up['card'])
            if card
              played_card = follow_up['card']
              played_card += follow_up['wild_color'][0] if follow_up['wild_color']
              @current_game_log << "#{top_card};#{player_name};#{hand_cards};#{played_card}"

              card.set_wild_color(follow_up['wild_color'].to_sym) if follow_up['wild_color']
              game.player_card_play(player, card)
            else
              @current_game_log << "#{top_card};#{player_name};#{hand_cards};pass"
              game.turn_pass
            end
          else
            @current_game_log << "#{top_card};#{player_name};#{hand_cards};pass"
            game.turn_pass
          end
        end
      when 'pass'
        @current_game_log << "#{top_card};#{player_name};#{hand_cards};pass"
        game.turn_pass
      end
    rescue StandardError => e
      @current_game_log << "#{top_card};#{player_name};#{hand_cards};error"
      if game.instance_variable_get(:@already_picked)
        game.turn_pass
      else
        game.pick_single
        game.turn_pass
      end
    end
  end

  def find_card(hand, card_string)
    if %w[w wd4].include?(card_string)
      hand.find do |c|
        (c.figure == 'wild' && card_string == 'w') ||
          (c.figure == 'wild+4' && card_string == 'wd4')
      end
    else
      hand.find { |c| c.to_s == card_string }
    end
  end

  def generate_final_results(duration)
    output = []
    output << "\n📊 FINAL TOURNAMENT RESULTS"
    output << '=' * 60
    output << "Tournament: #{@tournament_type}"
    output << "Total duration: #{duration.round(2)} seconds"
    output << ''

    if @tournament_type == 'round-robin'
      output << 'STANDINGS:'
      sorted_results = @results.sort_by { |_, stats| [-stats[:wins], stats[:games]] }

      sorted_results.each_with_index do |(agent, stats), idx|
        win_rate = (stats[:wins].to_f / stats[:games] * 100).round(1)
        output << "#{idx + 1}. #{agent}: #{stats[:wins]} wins / #{stats[:games]} games (#{win_rate}%)"
      end

      output << "\nHEAD-TO-HEAD RESULTS:"
      @match_results.each do |match|
        output << "#{match[:players].join(' vs ')}: #{match[:wins].map do |a, w|
          "#{a}=#{w}"
        end.join(', ')} → Winner: #{match[:winner]}"
      end

    elsif @tournament_type == 'elimination-bracket'
      # Find champion
      champion = @results.find { |_, stats| stats[:eliminated_round].nil? }[0]
      output << "🏆 CHAMPION: #{champion}"
      output << ''

      # Sort by elimination round (nil = champion, higher round = better)
      sorted = @results.sort_by do |_, stats|
        [-(stats[:eliminated_round] || Float::INFINITY), -stats[:wins]]
      end

      output << 'FINAL PLACEMENT:'
      sorted.each_with_index do |(agent, stats), idx|
        placement = idx + 1
        output << if stats[:eliminated_round]
                    "#{placement}. #{agent} (eliminated round #{stats[:eliminated_round]})"
                  else
                    "#{placement}. #{agent} (CHAMPION)"
                  end
        output << "   Games: #{stats[:games]}, Wins: #{stats[:wins]}, Win rate: #{(stats[:wins].to_f / stats[:games] * 100).round(1)}%"
      end
    end

    output.join("\n")
  end

  def save_game_logs
    return unless @game_log_file

    # Write to the configured game log file in real-time (already open)
    # This method is called at the end to ensure all logs are flushed
    @game_log.flush if @game_log

    log_output "Game logs saved to: #{@game_log_file}"
  end

  def analyze_lost_games
    # Find games where SmartRuby lost
    smart_agent_name = @agents.keys.find { |name| name.downcase.include?('smart') }
    return unless smart_agent_name

    lost_games = @game_logs.select do |g|
      g[:players].include?(smart_agent_name) && g[:winner] != smart_agent_name
    end

    # Analyze a sample of lost games
    sample_size = [5, lost_games.size].min
    sample = lost_games.sample(sample_size)

    log_output "\n📋 ANALYSIS OF LOST GAMES (#{sample_size} samples)", :header
    log_output '=' * 60, :header

    sample.each_with_index do |game_data, idx|
      log_output "\nGame Analysis #{idx + 1}:", :header
      log_output "Players: #{game_data[:players].join(' vs ')}, Winner: #{game_data[:winner]}"

      # Find potential mistakes
      mistakes = []
      game_log = game_data[:log]

      game_log.each_with_index do |turn, turn_idx|
        next if turn.include?('wins')

        parts = turn.split(';')
        next if parts.size < 4

        top_card, player, hand, action = parts

        next unless player == smart_agent_name

        # Check for potential mistakes
        hand_cards = hand.split(',')

        # Mistake 1: Drawing when had playable cards
        if action == 'draw' && hand_cards.any? { |c| could_play?(c, top_card) }
          mistakes << "Turn #{turn_idx}: Drew when had playable cards (#{hand_cards.select do |c|
            could_play?(c, top_card)
          end.join(', ')})"
        end

        # Mistake 2: Not playing action cards when opponent low
        next unless turn_idx > 0 && action != 'draw'

        prev_turn = game_log[turn_idx - 1]
        next unless prev_turn && !prev_turn.include?(smart_agent_name)

        prev_parts = prev_turn.split(';')
        next unless prev_parts.size >= 3

        opponent_hand_size = prev_parts[2].split(',').size
        next unless opponent_hand_size <= 3 && hand_cards.any? do |c|
          is_action_card?(c)
        end && !is_action_card?(action.split(/[rgby]/)[0])

        available_actions = hand_cards.select { |c| is_action_card?(c) && could_play?(c, top_card) }
        if available_actions.any?
          mistakes << "Turn #{turn_idx}: Didn't play action card when opponent had #{opponent_hand_size} cards (had: #{available_actions.join(', ')})"
        end
      end

      if mistakes.any?
        log_output 'Potential mistakes:'
        mistakes.each { |m| log_output "  - #{m}" }
      else
        log_output 'No obvious mistakes detected'
      end
    end
  end

  def could_play?(card, top_card)
    return true if %w[w wd4].include?(card)
    return false if card.empty? || top_card.empty?

    # Extract color and figure
    card_color = card[0]
    card_figure = card[1..]
    top_color = top_card[0]
    top_figure = top_card[1..]

    card_color == top_color || card_figure == top_figure
  end

  def is_action_card?(card)
    return true if card == 'wd4'
    return false if card.nil? || card.empty?

    figure = card[1..]
    ['s', 'r', 'd2', '+2'].include?(figure)
  end
end

# Run if called directly
if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: #{$0} <config.yaml>"
    puts "\nExample config.yaml:"
    puts 'agents:'
    puts "  SimpleRuby: './simple_agent.rb'"
    puts "  SimplePython: 'python3 simple_agent.py'"
    puts "  SmartRuby: './smart_agent.rb'"
    puts "tournament_type: round-robin  # or 'elimination-bracket'"
    puts 'games_per_round: 10'
    puts 'timeouts:'
    puts '  turn_timeout: 1.0   # seconds per turn (0 = no limit)'
    puts '  game_timeout: 10.0  # seconds per game (0 = no limit)'
    puts 'output:'
    puts '  stdout: true'
    puts '  log_file: tournament.log'
    puts '  log_results_file: results.txt'
    exit 1
  end

  runner = ConfiguredTournamentRunner.new(ARGV[0])
  runner.run
end
