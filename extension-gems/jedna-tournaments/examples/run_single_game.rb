#!/usr/bin/env ruby
# frozen_string_literal: true

# Run Single Game - Debug tool for testing individual games
#
# Runs a single game between two agents with full output, useful for:
# - Debugging agent behavior
# - Understanding game flow
# - Testing new strategies
# - Verifying agent communication
#
# Usage: ./run_single_game.rb <agent1_command> <agent2_command>
# Example: ./run_single_game.rb './simple_agent.rb' './smarter_agent.rb'

require 'bundler/setup'
require 'jedna'
require_relative '../lib/jedna_tournaments'

# Runs a single game between two agents for debugging
class SingleGameRunner
  TURN_TIMEOUT = 2.0
  GAME_TIMEOUT = 30

  def initialize(agent1_cmd, agent2_cmd)
    @agents = {
      'agent1' => create_agent(agent1_cmd, 'Agent1'),
      'agent2' => create_agent(agent2_cmd, 'Agent2')
    }
    @serializer = Jedna::GameStateSerializer.new
    @turn_count = 0
    @game_ended = false
  end

  def run
    display_header
    start_agents

    game = setup_game
    winner = run_game_loop(game)

    display_results(winner)
    winner
  ensure
    stop_agents
  end

  private

  def create_agent(command, name)
    JednaTournaments::ProcessAgent.new(command, name)
  end

  def display_header
    puts 'Starting game...'
    puts "#{@agents['agent1'].name} vs #{@agents['agent2'].name}"
    puts '-' * 40
  end

  def start_agents
    @agents.each_value(&:start)
  end

  def stop_agents
    @agents.each_value do |agent|
      agent.stop
    rescue StandardError
      # Ignore errors during cleanup
    end
  end

  def setup_game
    game = Jedna::Game.new('single_game')

    # Add players
    %w[agent1 agent2].each do |id|
      player = Jedna::Player.new(Jedna::SimpleIdentity.new(id))
      game.add_player(player)
    end

    # Set up event handlers
    game.before_player_turn { |g, player| handle_turn(g, player) }
    game.on_game_ended { handle_game_end(game) }

    game
  end

  def run_game_loop(game)
    game.start_game

    # Wait for completion
    start_time = Time.now
    sleep 0.1 while !@game_ended && (Time.now - start_time) < GAME_TIMEOUT

    puts "\nGame timed out after #{GAME_TIMEOUT} seconds" unless @game_ended

    game.players.first
  end

  def handle_turn(game, player)
    @turn_count += 1
    agent = @agents[player.identity.id]
    return unless agent

    state = @serializer.serialize_for_current_player(game)

    begin
      action = agent.request_action(state[:state], timeout: TURN_TIMEOUT)
      execute_action(game, player, action)
    rescue StandardError => e
      puts "Error: #{e.message}"
      handle_error(game)
    end
  end

  def execute_action(game, player, action)
    case action['action']
    when 'play'
      play_card(game, player, action)
    when 'draw'
      draw_and_maybe_play(game, player)
    when 'pass'
      game.turn_pass
    else
      puts "Unknown action: #{action['action']}"
      handle_error(game)
    end
  end

  def play_card(game, player, action)
    card = find_card_in_hand(player.hand, action['card'])
    return handle_error(game) unless card

    configure_wild_color(card, action['wild_color'])
    game.player_card_play(player, card)

    return unless action['double_play']

    begin
      game.player_card_play(player, card, true)
    rescue StandardError
      # Ignore if engine refuses
    end
  end

  def draw_and_maybe_play(game, player)
    game.pick_single

    return unless game.instance_variable_get(:@already_picked)

    # Allow playing drawn card
    new_state = @serializer.serialize_for_current_player(game)
    agent = @agents[player.identity.id]

    follow_up = agent.request_action(new_state[:state], timeout: TURN_TIMEOUT)

    if follow_up['action'] == 'play'
      play_card(game, player, follow_up)
    else
      game.turn_pass
    end
  end

  def handle_error(game)
    game.pick_single unless game.instance_variable_get(:@already_picked)
    game.turn_pass
  end

  def find_card_in_hand(hand, card_string)
    case card_string
    when 'w'
      hand.find { |c| c.figure == 'wild' }
    when 'wd4'
      hand.find { |c| c.figure == 'wild+4' }
    else
      hand.find { |c| c.to_s == card_string }
    end
  end

  def configure_wild_color(card, color_name)
    return unless color_name && ['wild', 'wild+4'].include?(card.figure)

    card.set_wild_color(color_name.to_sym)
  end

  def handle_game_end(game)
    @winner = game.players.first
    @scores = calculate_scores(game)

    display_game_over
    notify_agents_game_end

    @game_ended = true
  end

  def calculate_scores(game)
    game.players.to_h { |p| [p.identity.id, p.hand.value] }
  end

  def display_game_over
    puts "\n🎉 Game Over!"
    puts "Winner: #{@winner.identity.id} after #{@turn_count} turns"
    puts "Scores: #{@scores.inspect}"
  end

  def notify_agents_game_end
    @agents.each_value do |agent|
      agent.notify_game_end(@winner.identity.id, @scores)
    rescue StandardError
      # Ignore notification errors
    end
  end

  def display_results(winner)
    puts "\nFinal winner: #{winner&.identity&.id || 'None'}"
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  if ARGV.length < 2
    puts "Usage: #{$PROGRAM_NAME} <agent1_command> <agent2_command>"
    puts "Example: #{$PROGRAM_NAME} './simple_agent.rb' 'python3 simple_agent.py'"
    exit 1
  end

  runner = SingleGameRunner.new(ARGV[0], ARGV[1])
  runner.run
end
