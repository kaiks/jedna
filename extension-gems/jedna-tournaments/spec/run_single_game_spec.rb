# frozen_string_literal: true

require 'spec_helper'
require_relative '../examples/run_single_game'

# rubocop:disable Metrics/BlockLength
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

  describe '#execute_action' do
    it 'delegates complete protocol actions to the shared executor' do
      runner = described_class.allocate
      player = Jedna::Player.new('Alice')
      game = instance_double(Jedna::Game)
      action = { 'action' => 'play', 'card' => 'r5', 'double_play' => true }
      executor = instance_double(Jedna::ActionExecutor)
      result = Jedna::ActionResult.new(success: true, code: 'ok', message: nil, action: 'play')

      allow(Jedna::ActionExecutor).to receive(:new).with(game).and_return(executor)
      expect(executor).to receive(:execute).with(action, player: player).and_return(result)

      expect(runner.send(:execute_action, game, player, action)).to eq(result)
    end

    it 'falls back to draw and pass when the executor rejects an action' do
      runner = described_class.allocate
      player = Jedna::Player.new('Alice')
      game = instance_double(Jedna::Game)
      action = { 'action' => 'play', 'card' => 'r5' }
      executor = instance_double(Jedna::ActionExecutor)
      result = Jedna::ActionResult.new(
        success: false,
        code: 'card_not_playable',
        message: 'r5 is not playable',
        action: 'play'
      )

      allow(Jedna::ActionExecutor).to receive(:new).with(game).and_return(executor)
      allow(executor).to receive(:execute).and_return(result)
      expect(runner).to receive(:handle_error).with(game)

      runner.send(:execute_action, game, player, action)
    end
  end
end
# rubocop:enable Metrics/BlockLength
