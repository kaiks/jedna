require 'spec_helper'
require 'jedna/game_state_serializer'

RSpec.describe Jedna::GameStateSerializer do
  let(:serializer) { described_class.new }
  let(:game) { Jedna::Game.new('creator') }
  let(:player1) { Jedna::Player.new('player1') }
  let(:player2) { Jedna::Player.new('player2') }
  let(:player3) { Jedna::Player.new('player3') }

  before do
    game.add_player(player1)
    game.add_player(player2)
    game.add_player(player3)
  end

  describe '#serialize_for_current_player' do
    context 'before game starts' do
      it 'returns nil' do
        expect(serializer.serialize_for_current_player(game)).to be_nil
      end
    end

    context 'during normal game' do
      before do
        game.start_game
        # Set up a known game state for testing
        player1.hand.clear
        player1.hand << Jedna::Card.new(:red, 2)
        player1.hand << Jedna::Card.new(:blue, 5)
        player1.hand << Jedna::Card.new(:wild, 'wild+4')

        # Ensure player1 is current player
        game.instance_variable_set(:@players, [player1, player2, player3])
        game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 7))
      end

      it 'includes basic game information' do
        result = serializer.serialize_for_current_player(game)

        expect(result[:type]).to eq('request_action')
        expect(result[:state][:your_id]).to eq('player1')
        expect(result[:state][:game_state]).to eq('normal')
        expect(result[:state][:top_card]).to eq('r7')
      end

      it 'includes player hand' do
        result = serializer.serialize_for_current_player(game)

        expect(result[:state][:hand]).to eq(%w[r2 b5 wd4])
      end

      it 'includes other players info' do
        result = serializer.serialize_for_current_player(game)
        other_players = result[:state][:other_players]

        expect(other_players.length).to eq(2)
        expect(other_players[0][:id]).to eq('player2')
        expect(other_players[0][:cards]).to be_a(Integer)
        expect(other_players[1][:id]).to eq('player3')
      end

      it 'includes available actions' do
        result = serializer.serialize_for_current_player(game)
        actions = result[:state][:available_actions]

        expect(actions).to include('play')
        expect(actions).to include('draw')
        expect(actions).not_to include('pass') # Can't pass without drawing
      end

      it 'includes playable cards' do
        result = serializer.serialize_for_current_player(game)

        expect(result[:state][:playable_cards]).to eq(%w[r2 wd4])
      end
    end

    context 'during +2 war' do
      before do
        game.start_game
        game.instance_variable_set(:@game_state, 2)
        game.instance_variable_set(:@stacked_cards, 4)
      end

      it 'shows war state' do
        result = serializer.serialize_for_current_player(game)

        expect(result[:state][:game_state]).to eq('war_+2')
        expect(result[:state][:stacked_cards]).to eq(4)
      end
    end

    context 'during wd4 war' do
      before do
        game.start_game
        game.instance_variable_set(:@game_state, 3)
        game.instance_variable_set(:@stacked_cards, 8)
      end

      it 'shows wd4 war state' do
        result = serializer.serialize_for_current_player(game)

        expect(result[:state][:game_state]).to eq('war_wd4')
        expect(result[:state][:stacked_cards]).to eq(8)
      end
    end

    context 'after drawing a card' do
      before do
        game.start_game
        # Ensure player1 is current player with known top card and hand
        game.instance_variable_set(:@players, [player1, player2, player3])
        game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 7))
        player1.hand.clear
        # Include a couple of cards that are playable against r7
        player1.hand << Jedna::Card.new(:red, 2) # playable
        player1.hand << Jedna::Card.new(:wild, 'wild') # playable anywhere
        player1.hand << Jedna::Card.new(:green, 3) # will be set as picked (not playable)

        game.instance_variable_set(:@already_picked, true)
        game.instance_variable_set(:@picked_card, Jedna::Card.new(:green, 3))
      end

      it 'includes picked card info' do
        result = serializer.serialize_for_current_player(game)

        expect(result[:state][:already_picked]).to be true
        expect(result[:state][:picked_card]).to eq('g3')
        expect(result[:state][:available_actions]).to include('pass')
      end

      it 'exposes illegal plays after draw when picked card is not playable' do
        result = serializer.serialize_for_current_player(game)

        # According to rules, after drawing and before passing, only pass is allowed
        # because picked card (g3) is not playable on r7.
        expect(result[:state][:available_actions]).not_to include('draw')
        expect(result[:state][:available_actions]).not_to include('play'),
                                                          'should not offer play when picked card is not playable'

        # And no other hand cards should be suggested as playable
        expect(result[:state][:playable_cards]).to eq([])
      end

      it 'exposes whole-hand playable cards instead of only the picked card when it is playable' do
        # Make the picked card playable (set to r2) while keeping other playable cards in hand
        picked = Jedna::Card.new(:red, 2)
        game.instance_variable_set(:@picked_card, picked)

        result = serializer.serialize_for_current_player(game)

        # Expect only playing the picked card or passing (no draw)
        expect(result[:state][:available_actions]).to include('play')
        expect(result[:state][:available_actions]).to include('pass')
        expect(result[:state][:available_actions]).not_to include('draw')

        # Expect only the picked card to be listed as playable
        expect(result[:state][:playable_cards]).to eq(['r2'])
      end
    end

    context 'with special cards' do
      before do
        game.start_game
        # Ensure player1 is current player
        game.instance_variable_set(:@players, [player1, player2, player3])
        player1.hand.clear
        player1.hand << Jedna::Card.new(:red, 'skip')
        player1.hand << Jedna::Card.new(:blue, 'reverse')
        player1.hand << Jedna::Card.new(:green, '+2')
        player1.hand << Jedna::Card.new(:wild, 'wild')
      end

      it 'correctly serializes special cards' do
        result = serializer.serialize_for_current_player(game)

        expect(result[:state][:hand]).to eq(['rs', 'br', 'g+2', 'w'])
      end
    end
  end

  describe '#serialize_notification' do
    it 'creates a notification message' do
      result = serializer.serialize_notification('Player2 played r5')

      expect(result[:type]).to eq('notification')
      expect(result[:message]).to eq('Player2 played r5')
    end
  end

  describe '#serialize_error' do
    it 'creates an error message' do
      result = serializer.serialize_error('Invalid card')

      expect(result[:type]).to eq('error')
      expect(result[:message]).to eq('Invalid card')
    end
  end

  describe '#serialize_game_end' do
    before do
      game.add_player(player1)
      game.add_player(player2)
      game.start_game

      # Set up end game state
      player1.hand.clear # Winner
      player2.hand.clear
      player2.hand << Jedna::Card.new(:red, 5)
      player2.hand << Jedna::Card.new(:blue, 3)
      player3.hand.clear
      player3.hand << Jedna::Card.new(:green, 7)
    end

    it 'creates game end message with scores' do
      result = serializer.serialize_game_end(game, player1)

      expect(result[:type]).to eq('game_end')
      expect(result[:winner]).to eq('player1')
      expect(result[:scores]).to eq({
                                      'player1' => 0,
                                      'player2' => 8,
                                      'player3' => 7
                                    })
    end
  end
end
