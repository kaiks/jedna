require 'spec_helper'

RSpec.describe Jedna::Game, 'hooks' do
  let(:game) { described_class.new('creator') }
  let(:player1) { Jedna::Player.new('player1') }
  let(:player2) { Jedna::Player.new('player2') }
  
  before do
    game.add_player(player1)
    game.add_player(player2)
  end
  
  describe '#before_player_turn' do
    it 'calls the hook before each player turn' do
      turn_data = []
      
      game.before_player_turn do |current_game, current_player|
        turn_data << {
          player: current_player.identity.id,
          hand_size: current_player.hand.size,
          top_card: current_game.top_card.to_s
        }
      end
      
      game.start_game
      
      # Should have been called for first player's turn
      expect(turn_data.size).to eq(1)
      expect(turn_data[0][:player]).to be_a(String)
      expect(turn_data[0][:hand_size]).to be > 0
      expect(turn_data[0][:top_card]).to be_a(String)
    end
    
    it 'allows multiple hooks to be registered' do
      hook1_called = false
      hook2_called = false
      
      game.before_player_turn { hook1_called = true }
      game.before_player_turn { hook2_called = true }
      
      game.start_game
      
      expect(hook1_called).to be true
      expect(hook2_called).to be true
    end
    
    it 'passes the correct player as current' do
      current_player_id = nil
      
      game.before_player_turn do |_, player|
        current_player_id = player.identity.id
      end
      
      game.start_game
      
      # The current player should be game.players[0]
      expect(current_player_id).to eq(game.players[0].identity.id)
    end
    
    it 'is called again after a turn' do
      call_count = 0
      
      game.before_player_turn { call_count += 1 }
      
      game.start_game
      expect(call_count).to eq(1)
      
      # Simulate a turn by having player draw and pass
      game.pick_single
      game.turn_pass
      
      expect(call_count).to eq(2)
    end
    
    it 'provides access to full game state' do
      game_state_captured = nil
      
      game.before_player_turn do |current_game, _|
        game_state_captured = {
          state: current_game.game_state,
          players_count: current_game.players.size,
          top_card: current_game.top_card.to_s
        }
      end
      
      game.start_game
      
      expect(game_state_captured[:state]).to eq(1) # Normal game state
      expect(game_state_captured[:players_count]).to eq(2)
      expect(game_state_captured[:top_card]).to be_a(String)
    end
    
    context 'with exceptions in hook' do
      it 'does not prevent game from continuing if hook raises' do
        game.before_player_turn { raise "Hook error" }
        
        # Game should start without raising
        expect { game.start_game }.not_to raise_error
        
        # Game should be in started state
        expect(game.started?).to be true
      end
    end
  end
  
  describe 'integration with GameStateSerializer' do
    it 'can serialize state in the hook' do
      serializer = Jedna::GameStateSerializer.new
      serialized_state = nil
      
      game.before_player_turn do |current_game, current_player|
        serialized_state = serializer.serialize_for_current_player(current_game)
      end
      
      game.start_game
      
      expect(serialized_state).to be_a(Hash)
      expect(serialized_state[:type]).to eq('request_action')
      expect(serialized_state[:state][:your_id]).to eq(game.players[0].identity.id)
    end
  end
end