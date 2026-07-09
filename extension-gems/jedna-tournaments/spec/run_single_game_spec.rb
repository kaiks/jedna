# frozen_string_literal: true

require 'spec_helper'
require_relative '../examples/run_single_game'

RSpec.describe SingleGameRunner do
  describe '#run_game_loop' do
    it 'drives turns explicitly after starting the game' do
      runner = described_class.allocate
      runner.instance_variable_set(:@game_ended, false)
      player = Jedna::Player.new('agent1')
      game = instance_double(Jedna::Game, players: [player])
      allow(game).to receive(:start_game).with(nil, 'agent1')
      allow(runner).to receive(:handle_turn) do
        runner.instance_variable_set(:@game_ended, true)
      end

      winner = runner.send(:run_game_loop, game)

      expect(winner).to eq(player)
      expect(runner).to have_received(:handle_turn).with(game, player).once
    end
  end

  describe '#play_card' do
    it 'passes the double-play option on the original play' do
      runner = described_class.allocate
      card = Jedna::Card.new(:red, 5)
      player = Jedna::Player.new('Alice')
      player.hand << card
      game = instance_double(Jedna::Game)
      action = { 'action' => 'play', 'card' => 'r5', 'double_play' => true }

      expect(game).to receive(:player_card_play).with(player, card, true).and_return(true)

      runner.send(:play_card, game, player, action)
    end

    it 'falls back to draw and pass when a play is rejected' do
      runner = described_class.allocate
      card = Jedna::Card.new(:red, 5)
      player = Jedna::Player.new('Alice')
      player.hand << card
      game = instance_double(Jedna::Game, started?: true, already_picked: false)
      action = { 'action' => 'play', 'card' => 'r5' }

      expect(game).to receive(:player_card_play).with(player, card, false).and_return(false)
      expect(game).to receive(:pick_single).ordered
      expect(game).to receive(:turn_pass).ordered

      runner.send(:play_card, game, player, action)
    end
  end
end
