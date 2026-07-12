# frozen_string_literal: true

require 'json'
require 'spec_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe 'automated-play protocol fixtures' do
  subject(:serialized) do
    JSON.parse(JSON.generate(Jedna::GameStateSerializer.new.serialize_for_current_player(game)))
  end

  let(:fixture_directory) { File.expand_path('fixtures/protocol', __dir__) }
  let(:other_hands) { [%w[b1 g2], %w[y3]] }

  def build_game(hand:, top_card:, game_state:, stacked_cards:, picked_card: nil)
    players = %w[Alice Bob Carol].map { |name| Jedna::Player.new(name) }
    game = game_with_players(players)
    populate_hands(players, hand)
    state = { top_card: top_card, game_state: game_state, stacked_cards: stacked_cards, picked_card: picked_card }
    configure_state(game, players.first, state)
    game
  end

  def game_with_players(players)
    game = TestJednaGame.new('creator', 1)
    players.each { |player| game.add_player(player) }
    game.instance_variable_set(:@players, players)
    game
  end

  def populate_hands(players, hand)
    players.first.hand << hand.map { |card| Jedna::Card.parse(card) }
    other_hands.each_with_index do |cards, index|
      players[index + 1].hand << cards.map { |card| Jedna::Card.parse(card) }
    end
  end

  def configure_state(game, player, state)
    game.instance_variable_set(:@top_card, Jedna::Card.parse(state[:top_card]))
    game.instance_variable_set(:@game_state, state[:game_state])
    game.instance_variable_set(:@stacked_cards, state[:stacked_cards])
    game.instance_variable_set(:@already_picked, !state[:picked_card].nil?)
    game.instance_variable_set(:@picked_card, player.hand.find_card(state[:picked_card]))
  end

  def fixture(name)
    JSON.parse(File.read(File.join(fixture_directory, "#{name}.json")))
  end

  context 'with a normal turn' do
    let(:game) do
      build_game(
        hand: %w[r2 b5 wd4],
        top_card: 'r7',
        game_state: 1,
        stacked_cards: 0
      )
    end

    it { is_expected.to eq(fixture('request_action_normal')) }
  end

  context 'with a playable card drawn this turn' do
    let(:game) do
      build_game(
        hand: %w[g3 r5],
        top_card: 'r7',
        game_state: 1,
        stacked_cards: 0,
        picked_card: 'r5'
      )
    end

    it { is_expected.to eq(fixture('request_action_after_draw')) }
  end

  context 'with a draw-two war' do
    let(:game) do
      build_game(
        hand: %w[r+2 rr wd4 b5],
        top_card: 'r+2',
        game_state: 2,
        stacked_cards: 4
      )
    end

    it { is_expected.to eq(fixture('request_action_plus_two_war')) }
  end

  context 'with a wild-draw-four war' do
    let(:game) do
      build_game(
        hand: %w[wd4 gr g+2 b5],
        top_card: 'wd4g',
        game_state: 3,
        stacked_cards: 8
      )
    end

    it { is_expected.to eq(fixture('request_action_wd4_war')) }
  end
end
# rubocop:enable Metrics/BlockLength
