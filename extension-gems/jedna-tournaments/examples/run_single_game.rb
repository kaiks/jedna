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

class SingleGameRunner
  def initialize(agent1_cmd, agent2_cmd)
    @agent1 = JednaTournaments::ProcessAgent.new(agent1_cmd, 'Agent1')
    @agent2 = JednaTournaments::ProcessAgent.new(agent2_cmd, 'Agent2')
    @serializer = Jedna::GameStateSerializer.new
  end

  def run
    puts 'Starting game...'
    puts "#{@agent1.name} vs #{@agent2.name}"
    puts '-' * 40

    # Start agents
    @agent1.start
    @agent2.start

    # Create game
    game = Jedna::Game.new('single_game')

    # Add players
    player1 = Jedna::Player.new(Jedna::SimpleIdentity.new('agent1'))
    player2 = Jedna::Player.new(Jedna::SimpleIdentity.new('agent2'))

    game.add_player(player1)
    game.add_player(player2)

    # Map players to agents
    @player_agent_map = {
      'agent1' => @agent1,
      'agent2' => @agent2
    }

    winner = nil
    turn_count = 0
    game_ended = false

    # Set up hooks
    game.before_player_turn do |g, current_player|
      turn_count += 1
      handle_turn(g, current_player)
    end

    game.on_game_ended do
      winner = game.players[0]
      scores = {}
      game.players.each do |p|
        scores[p.identity.id] = p.hand.value
      end

      puts "\n🎉 Game Over!"
      puts "Winner: #{winner.identity.id} after #{turn_count} turns"
      puts "Scores: #{scores.inspect}"

      # Notify agents
      @player_agent_map.each_value do |agent|
        agent.notify_game_end(winner.identity.id, scores)
      rescue StandardError
        nil
      end

      # Mark game as ended
      game_ended = true
    end

    # Start and run game
    game.start_game

    # Wait for completion (max 30 seconds)
    timeout = 30
    start_time = Time.now
    sleep 0.1 while !game_ended && (Time.now - start_time) < timeout

    puts "\nGame timed out after #{timeout} seconds" unless game_ended

    winner
  ensure
    begin
      @agent1.stop
    rescue StandardError
      nil
    end
    begin
      @agent2.stop
    rescue StandardError
      nil
    end
  end

  private

  def handle_turn(game, player)
    agent = @player_agent_map[player.identity.id]
    return unless agent

    state = @serializer.serialize_for_current_player(game)

    begin
      action = agent.request_action(state[:state], timeout: 2.0)

      case action['action']
      when 'play'
        card = find_card(player.hand, action['card'])
        if card
          card.set_wild_color(action['wild_color'].to_sym) if action['wild_color']
          game.player_card_play(player, card)
        end
      when 'draw'
        game.pick_single
        # Allow playing drawn card
        if game.instance_variable_get(:@already_picked)
          new_state = @serializer.serialize_for_current_player(game)
          follow_up = agent.request_action(new_state[:state], timeout: 2.0)

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
    rescue StandardError => e
      puts "Error: #{e.message}"
      # Default action
      game.pick_single unless game.instance_variable_get(:@already_picked)
      game.turn_pass
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
end

# Run if called directly
if __FILE__ == $PROGRAM_NAME
  if ARGV.length < 2
    puts "Usage: #{$PROGRAM_NAME} <agent1_command> <agent2_command>"
    puts "Example: #{$PROGRAM_NAME} './simple_agent.rb' 'python3 simple_agent.py'"
    exit 1
  end

  runner = SingleGameRunner.new(ARGV[0], ARGV[1])
  runner.run
end
