# frozen_string_literal: true

require 'spec_helper'
require_relative '../examples/run_single_game'

RSpec.describe SingleGameRunner do
  describe '#play_card' do
    it 'passes the double-play option on the original play' do
      runner = described_class.allocate
      card = Jedna::Card.new(:red, 5)
      player = Jedna::Player.new('Alice')
      player.hand << card
      game = instance_double(Jedna::Game)
      action = { 'action' => 'play', 'card' => 'r5', 'double_play' => true }

      expect(game).to receive(:player_card_play).with(player, card, true)

      runner.send(:play_card, game, player, action)
    end
  end
end
