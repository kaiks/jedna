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

  it 'runs after legacy before-turn hooks' do
    calls = []
    game.before_player_turn { calls << :before_player_turn }
    game.on_action_required { calls << :action_required }

    game.start_game(nil, 'Alice')

    expect(calls).to eq(%i[before_player_turn action_required])
  end

  it 'keeps a thread-safe game locked until the event callback returns' do
    thread_safe_game_class = Class.new(Jedna::Game) { include ThreadSafeGame }
    thread_safe_game = thread_safe_game_class.new('creator', 1, Jedna::NullNotifier.new)
    thread_safe_game.add_player(alice)
    thread_safe_game.add_player(bob)
    hook_entered = Queue.new
    release_hook = Queue.new
    read_completed = Queue.new
    thread_safe_game.on_action_required do |_, _, reason|
      next unless reason == :card_drawn

      hook_entered << true
      release_hook.pop
    end
    thread_safe_game.start_game(nil, 'Alice')

    drawing = Thread.new { thread_safe_game.pick_single }
    hook_entered.pop
    reading = Thread.new { read_completed << thread_safe_game.picked_card }

    expect(reading.join(0.05)).to be_nil
    expect { read_completed.pop(true) }.to raise_error(ThreadError)

    release_hook << true
    drawing.join
    reading.join
    expect(read_completed.pop).not_to be_nil
  end
end
# rubocop:enable Metrics/BlockLength
