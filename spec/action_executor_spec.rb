# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Jedna::ActionExecutor do
  subject(:executor) { described_class.new(game) }

  let(:game) { TestJednaGame.new('creator', 1) }
  let(:alice) { Jedna::Player.new('Alice') }
  let(:bob) { Jedna::Player.new('Bob') }
  let(:current_player) { game.players.first }

  before do
    game.add_player(alice)
    game.add_player(bob)
    game.start_game(nil, 'Alice')
    current_player.hand.clear
    game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 7))
    game.instance_variable_set(:@game_state, 1)
    game.instance_variable_set(:@stacked_cards, 0)
  end

  describe '#execute' do
    it 'plays a card and returns a structured success result' do
      current_player.hand << Jedna::Card.new(:red, 5)
      current_player.hand << Jedna::Card.new(:green, 3)

      result = executor.execute('action' => 'play', 'card' => 'r5')

      expect(result).to be_success
      expect(result.to_h).to eq(success: true, code: 'ok', message: nil, action: 'play')
      expect(current_player.hand.map(&:to_s)).to eq(['g3'])
      expect(game.top_card.to_s).to eq('r5')
    end

    it 'configures a wild color before playing' do
      current_player.hand << Jedna::Card.new(:wild, 'wild')
      current_player.hand << Jedna::Card.new(:green, 3)

      result = executor.execute(action: 'play', card: 'w', wild_color: 'blue')

      expect(result).to be_success
      expect(game.top_card.to_s).to eq('wb')
    end

    it 'plays matching cards as a double play' do
      current_player.hand << Jedna::Card.new(:red, 5)
      current_player.hand << Jedna::Card.new(:red, 5)
      current_player.hand << Jedna::Card.new(:green, 3)

      result = executor.execute('action' => 'play', 'card' => 'r5', 'double_play' => true)

      expect(result).to be_success
      expect(current_player.hand.map(&:to_s)).to eq(['g3'])
    end

    it 'draws a card when drawing is available' do
      current_player.hand << Jedna::Card.new(:green, 3)

      expect { @result = executor.execute('action' => 'draw') }.to change(current_player.hand, :size).by(1)
      expect(@result).to be_success
      expect(game.already_picked).to be(true)
    end

    it 'passes after drawing' do
      current_player.hand << Jedna::Card.new(:green, 3)
      executor.execute('action' => 'draw')

      result = executor.execute('action' => 'pass')

      expect(result).to be_success
      expect(game.players.first).to eq(bob)
    end

    it 'accepts a war penalty through pass' do
      current_player.hand << Jedna::Card.new(:green, 3)
      game.instance_variable_set(:@game_state, 2)
      game.instance_variable_set(:@stacked_cards, 4)

      expect { @result = executor.execute('action' => 'pass') }.to change(current_player.hand, :size).by(4)
      expect(@result).to be_success
      expect(game.stacked_cards).to eq(0)
    end

    it 'rejects malformed and unknown actions without changing the game' do
      current_player.hand << Jedna::Card.new(:red, 5)

      malformed = executor.execute(nil)
      unknown = executor.execute('action' => 'dance')

      expect(malformed.to_h).to include(success: false, code: 'invalid_action')
      expect(unknown.to_h).to include(success: false, code: 'invalid_action')
      expect(current_player.hand.map(&:to_s)).to eq(['r5'])
    end

    it 'rejects actions by a player whose turn it is not' do
      current_player.hand << Jedna::Card.new(:red, 5)

      result = executor.execute({ 'action' => 'play', 'card' => 'r5' }, player: bob)

      expect(result).to be_error
      expect(result.code).to eq('not_current_player')
      expect(current_player.hand.map(&:to_s)).to eq(['r5'])
    end

    it 'rejects actions that are unavailable in the current state' do
      current_player.hand << Jedna::Card.new(:red, 5)

      result = executor.execute('action' => 'pass')

      expect(result).to be_error
      expect(result.code).to eq('action_unavailable')
    end

    it 'rejects cards that are not playable' do
      current_player.hand << Jedna::Card.new(:green, 5)
      current_player.hand << Jedna::Card.new(:red, 2)

      result = executor.execute('action' => 'play', 'card' => 'g5')

      expect(result).to be_error
      expect(result.code).to eq('card_not_playable')
      expect(current_player.hand.map(&:to_s)).to eq(%w[g5 r2])
    end

    it 'requires a valid color for wild cards' do
      current_player.hand << Jedna::Card.new(:wild, 'wild+4')

      missing = executor.execute('action' => 'play', 'card' => 'wd4')
      invalid = executor.execute('action' => 'play', 'card' => 'wd4', 'wild_color' => 'purple')

      expect(missing.code).to eq('wild_color_required')
      expect(invalid.code).to eq('invalid_wild_color')
      expect(current_player.hand.first.color).to eq(:wild)
    end

    it 'rejects an unavailable double play without partially playing the first card' do
      current_player.hand << Jedna::Card.new(:red, 5)

      result = executor.execute('action' => 'play', 'card' => 'r5', 'double_play' => true)

      expect(result.code).to eq('double_play_unavailable')
      expect(current_player.hand.map(&:to_s)).to eq(['r5'])
      expect(game.top_card.to_s).to eq('r7')
    end

    it 'rejects double play after drawing' do
      picked = Jedna::Card.new(:red, 5)
      current_player.hand << picked
      current_player.hand << Jedna::Card.new(:red, 5)
      game.instance_variable_set(:@already_picked, true)
      game.instance_variable_set(:@picked_card, picked)

      result = executor.execute('action' => 'play', 'card' => 'r5', 'double_play' => true)

      expect(result.code).to eq('double_play_unavailable')
      expect(current_player.hand.size).to eq(2)
    end

    it 'validates and applies an action atomically for a thread-safe game' do
      thread_safe_class = Class.new(Jedna::Game) { include ThreadSafeGame }
      thread_safe_game = thread_safe_class.new('creator', 1, Jedna::NullNotifier.new)
      thread_safe_game.add_player(Jedna::Player.new('Alice'))
      thread_safe_game.add_player(Jedna::Player.new('Bob'))
      thread_safe_game.start_game(nil, 'Alice')
      alice = thread_safe_game.players.first
      alice.hand.clear
      alice.hand << Jedna::Card.new(:red, 5)
      alice.hand << Jedna::Card.new(:green, 3)
      thread_safe_game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 7))
      thread_safe_executor = described_class.new(thread_safe_game)
      original_serializer = Jedna::GameStateSerializer.new
      serialization_started = Queue.new
      release_serialization = Queue.new
      serializer = Object.new
      serializer.define_singleton_method(:serialize_for_current_player) do |current_game|
        serialization_started << true
        release_serialization.pop
        original_serializer.serialize_for_current_player(current_game)
      end
      thread_safe_executor.instance_variable_set(:@serializer, serializer)
      result = Queue.new
      execution = Thread.new do
        result << thread_safe_executor.execute('action' => 'play', 'card' => 'r5')
      end
      serialization_started.pop
      competing_started = Queue.new
      competing_action = Thread.new do
        competing_started << true
        thread_safe_game.pick_single
      end
      competing_started.pop

      expect(competing_action.join(0.05)).to be_nil

      release_serialization << true
      execution.join
      competing_action.join
      expect(result.pop).to be_success
      expect(thread_safe_game.top_card.to_s).to eq('r5')
    end
  end
end
# rubocop:enable Metrics/BlockLength
