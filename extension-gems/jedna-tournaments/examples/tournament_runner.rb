#!/usr/bin/env ruby
# Tournament runner configured via YAML file

require 'bundler/setup'
require 'jedna'
require 'yaml'
require_relative '../lib/jedna_tournaments'

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
    
    # Timeout configuration (0 or nil means no timeout)
    @turn_timeout = @config.dig('timeouts', 'turn_timeout') || 1.0
    @game_timeout = @config.dig('timeouts', 'game_timeout') || 10.0
    @turn_timeout = nil if @turn_timeout == 0
    @game_timeout = nil if @game_timeout == 0
    
    @serializer = Jedna::GameStateSerializer.new
    @results = {}
    @match_results = []
    
    # Set up logging
    if @log_file
      @log = File.open(@log_file, 'w')
    end
  end
  
  def run
    log_output "🏆 Jedna Tournament", :header
    log_output "=" * 60, :header
    log_output "Tournament Type: #{@tournament_type}"
    log_output "Games per round: #{@games_per_round}"
    log_output "Agents: #{@agents.keys.join(', ')}"
    log_output "Turn timeout: #{@turn_timeout ? "#{@turn_timeout}s" : 'none'}"
    log_output "Game timeout: #{@game_timeout ? "#{@game_timeout}s" : 'none'}"
    log_output "=" * 60, :header
    log_output ""
    
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
    
  ensure
    @log&.close
  end
  
  private
  
  def validate_config!
    raise "No agents configured" unless @config['agents'] && !@config['agents'].empty?
    raise "At least 2 agents required" if @config['agents'].size < 2
    
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
    if @stdout_output || type == :results
      puts message
    end
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
        if game_num.even?
          winner = play_game(agent1_name, agent2_name)
        else
          winner = play_game(agent2_name, agent1_name)
        end
        
        wins[winner] += 1 if winner
        print "." if @stdout_output
      end
      
      log_output " Complete!" if @stdout_output
      
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
      log_output "-" * 40, :header
      
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
          if game_num.even?
            winner = play_game(agent1_name, agent2_name)
          else
            winner = play_game(agent2_name, agent1_name)
          end
          
          wins[winner] += 1 if winner
          print "." if @stdout_output
        end
        
        log_output " Complete!" if @stdout_output
        
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
      
      winner_id = nil
      
      game.before_player_turn do |g, current_player|
        handle_turn(g, current_player, player_agent_map)
      end
      
      game.on_game_ended do
        winner = game.players[0]
        winner_id = winner.identity.id
        
        # Notify agents
        scores = {}
        game.players.each { |p| scores[p.identity.id] = p.hand.value }
        player_agent_map.each do |_, agent|
          agent.notify_game_end(winner_id, scores) rescue nil
        end
      end
      
      game.start_game
      
      # Wait for game completion
      if @game_timeout
        start = Time.now
        while game.started? && (Time.now - start) < @game_timeout
          sleep 0.05
        end
        
        if game.started?
          log_output "Game timeout after #{@game_timeout}s"
        end
      else
        # No timeout - wait until game ends
        while game.started?
          sleep 0.05
        end
      end
      
      winner_id
      
    rescue => e
      log_output "Error in game: #{e.message}"
      nil
    ensure
      agent1.stop rescue nil
      agent2.stop rescue nil
    end
  end
  
  def handle_turn(game, player, agent_map)
    agent = agent_map[player.identity.id]
    return unless agent
    
    state = @serializer.serialize_for_current_player(game)
    
    begin
      action = agent.request_action(state[:state], timeout: @turn_timeout)
      
      case action['action']
      when 'play'
        card = find_card(player.hand, action['card'])
        if card
          card.set_wild_color(action['wild_color'].to_sym) if action['wild_color']
          game.player_card_play(player, card)
        end
      when 'draw'
        game.pick_single
        if game.instance_variable_get(:@already_picked)
          new_state = @serializer.serialize_for_current_player(game)
          follow_up = agent.request_action(new_state[:state], timeout: @turn_timeout)
          
          case follow_up['action']
          when 'play'
            card = find_card(player.hand, follow_up['card'])
            if card
              card.set_wild_color(follow_up['wild_color'].to_sym) if follow_up['wild_color']
              game.player_card_play(player, card)
            else
              game.turn_pass
            end
          else
            game.turn_pass
          end
        end
      when 'pass'
        game.turn_pass
      end
    rescue => e
      if game.instance_variable_get(:@already_picked)
        game.turn_pass
      else
        game.pick_single
        game.turn_pass
      end
    end
  end
  
  def find_card(hand, card_string)
    if card_string == 'w' || card_string == 'wd4'
      hand.find { |c| 
        (c.figure == 'wild' && card_string == 'w') || 
        (c.figure == 'wild+4' && card_string == 'wd4')
      }
    else
      hand.find { |c| c.to_s == card_string }
    end
  end
  
  def generate_final_results(duration)
    output = []
    output << "\n📊 FINAL TOURNAMENT RESULTS"
    output << "=" * 60
    output << "Tournament: #{@tournament_type}"
    output << "Total duration: #{duration.round(2)} seconds"
    output << ""
    
    if @tournament_type == 'round-robin'
      output << "STANDINGS:"
      sorted_results = @results.sort_by { |_, stats| [-stats[:wins], stats[:games]] }
      
      sorted_results.each_with_index do |(agent, stats), idx|
        win_rate = (stats[:wins].to_f / stats[:games] * 100).round(1)
        output << "#{idx + 1}. #{agent}: #{stats[:wins]} wins / #{stats[:games]} games (#{win_rate}%)"
      end
      
      output << "\nHEAD-TO-HEAD RESULTS:"
      @match_results.each do |match|
        output << "#{match[:players].join(' vs ')}: #{match[:wins].map { |a, w| "#{a}=#{w}" }.join(', ')} → Winner: #{match[:winner]}"
      end
      
    elsif @tournament_type == 'elimination-bracket'
      # Find champion
      champion = @results.find { |_, stats| stats[:eliminated_round].nil? }[0]
      output << "🏆 CHAMPION: #{champion}"
      output << ""
      
      # Sort by elimination round (nil = champion, higher round = better)
      sorted = @results.sort_by do |_, stats|
        [-((stats[:eliminated_round] || Float::INFINITY)), -stats[:wins]]
      end
      
      output << "FINAL PLACEMENT:"
      sorted.each_with_index do |(agent, stats), idx|
        placement = idx + 1
        if stats[:eliminated_round]
          output << "#{placement}. #{agent} (eliminated round #{stats[:eliminated_round]})"
        else
          output << "#{placement}. #{agent} (CHAMPION)"
        end
        output << "   Games: #{stats[:games]}, Wins: #{stats[:wins]}, Win rate: #{(stats[:wins].to_f / stats[:games] * 100).round(1)}%"
      end
    end
    
    output.join("\n")
  end
end

# Run if called directly
if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: #{$0} <config.yaml>"
    puts "\nExample config.yaml:"
    puts "agents:"
    puts "  SimpleRuby: './simple_agent.rb'"
    puts "  SimplePython: 'python3 simple_agent.py'"
    puts "  SmartRuby: './smart_agent.rb'"
    puts "tournament_type: round-robin  # or 'elimination-bracket'"
    puts "games_per_round: 10"
    puts "timeouts:"
    puts "  turn_timeout: 1.0   # seconds per turn (0 = no limit)"
    puts "  game_timeout: 10.0  # seconds per game (0 = no limit)"
    puts "output:"
    puts "  stdout: true"
    puts "  log_file: tournament.log"
    puts "  log_results_file: results.txt"
    exit 1
  end
  
  runner = ConfiguredTournamentRunner.new(ARGV[0])
  runner.run
end