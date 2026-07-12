# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Jedna::Game, '#on_action_required' do
  let(:game) { TestJednaGame.new('creator', 1) }
  let(:alice) { Jedna::Player.new('Alice') }
  let(:bob) { Jedna::Player.new('Bob') }

  before do
    game.add_player(alice)
    game.add_player(bob)
  end

  it 'fires when the first turn starts' do
    events = []
    game.on_action_required do |current_game, player, reason|
      events << [current_game, player, reason]
    end

    game.start_game(nil, 'Alice')

    expect(events).to eq([[game, alice, :turn_started]])
  end

  it 'fires after a draw with the complete follow-up decision state' do
    states = []
    serializer = Jedna::GameStateSerializer.new
    game.on_action_required do |current_game, player, reason|
      states << [player, reason, serializer.serialize_for_current_player(current_game)]
    end
    game.start_game(nil, 'Alice')

    game.pick_single

    player, reason, request = states.last
    expect(player).to eq(alice)
    expect(reason).to eq(:card_drawn)
    expect(request[:state]).to include(
      already_picked: true,
      picked_card: game.picked_card.to_s
    )
    expect(request[:state][:available_actions]).to include('pass')
    expect(request[:state][:available_actions]).not_to include('draw')
  end

  it 'fires again when play advances to a new turn' do
    events = []
    game.on_action_required { |_, player, reason| events << [player, reason] }
    game.start_game(nil, 'Alice')

    game.pick_single
    game.turn_pass

    expect(events).to eq(
      [
        [alice, :turn_started],
        [alice, :card_drawn],
        [bob, :turn_started]
      ]
    )
  end

  it 'does not fire when a draw request is rejected' do
    reasons = []
    game.on_action_required { |_, _, reason| reasons << reason }
    game.start_game(nil, 'Alice')

    game.pick_single
    game.pick_single

    expect(reasons).to eq(%i[turn_started card_drawn])
  end

  it 'allows multiple hooks and isolates hook errors' do
    successful_calls = 0
    game.on_action_required { raise 'broken transport' }
    game.on_action_required { successful_calls += 1 }

    expect { game.start_game(nil, 'Alice') }.not_to raise_error
    expect(successful_calls).to eq(1)
    expect(game).to be_started
  end
end
# rubocop:enable Metrics/BlockLength
