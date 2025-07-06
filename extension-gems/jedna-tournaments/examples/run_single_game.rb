#!/usr/bin/env ruby
# Run a single game between two agents

require 'bundler/setup'
require 'jedna'
require_relative '../lib/jedna_tournaments'

class SingleGameRunner
  def initialize(agent1_cmd, agent2_cmd)
    @agent1 = JednaTournaments::ProcessAgent.new(agent1_cmd, "Agent1")
    @agent2 = JednaTournaments::ProcessAgent.new(agent2_cmd, "Agent2")
    @serializer = Jedna::GameStateSerializer.new
  end
  
  def run
    puts "Starting game..."
    puts "#{@agent1.name} vs #{@agent2.name}"
    puts "-" * 40
    
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
      @player_agent_map.each do |_, agent|
        agent.notify_game_end(winner.identity.id, scores) rescue nil
      end
    end
    
    # Start and run game
    game.start_game
    
    # Wait for completion (max 30 seconds)
    timeout = 30
    start_time = Time.now
    while game.started? && (Time.now - start_time) < timeout
      sleep 0.1
    end
    
    if game.started?
      puts "\nGame timed out after #{timeout} seconds"
    end
    
    winner
    
  ensure
    @agent1.stop rescue nil
    @agent2.stop rescue nil
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
    rescue => e
      puts "Error: #{e.message}"
      # Default action
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
end

# Run if called directly
if __FILE__ == $0
  if ARGV.length < 2
    puts "Usage: #{$0} <agent1_command> <agent2_command>"
    puts "Example: #{$0} './simple_agent.rb' 'python3 simple_agent.py'"
    exit 1
  end
  
  runner = SingleGameRunner.new(ARGV[0], ARGV[1])
  runner.run
end