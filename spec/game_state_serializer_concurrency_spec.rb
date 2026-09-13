# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Jedna::GameStateSerializer, 'synchronized snapshots' do
  let(:serializer) { described_class.new }
  let(:game_class) { Class.new(Jedna::Game) { include ThreadSafeGame } }
  let(:game) { game_class.new('creator', 1, Jedna::NullNotifier.new) }
  let(:alice) { Jedna::Player.new('Alice') }
  let(:bob) { Jedna::Player.new('Bob') }

  before do
    game.add_player(alice)
    game.add_player(bob)
    game.start_game(Jedna::CardStack.new.fill, 'Alice')
    alice.hand = Jedna::Hand.new(%w[r5 b1].map { |code| Jedna::Card.parse(code) })
  end

  it 'holds the monitor for the entire snapshot during a competing play' do
    entered = Queue.new
    release = Queue.new
    attempting_play = Queue.new
    allow(serializer).to receive(:calculate_playable_cards).and_wrap_original do |original, *args|
      entered << true
      release.pop
      original.call(*args)
    end

    reading = Thread.new { serializer.serialize_for_current_player(game) }
    entered.pop
    playing = Thread.new do
      attempting_play << true
      Jedna::ActionExecutor.new(game).execute(action: 'play', card: 'r5')
    end
    attempting_play.pop
    expect(playing.join(0.05)).to be_nil
    release << true

    state = reading.value[:state]
    expect(playing.value).to be_success
    expect(state).to include(your_id: 'Alice', top_card: 'r0', hand: %w[r5 b1])
    expect(state[:other_players].map { |player| player[:id] }).to eq(['Bob'])
    expect(game.players.first).to equal(bob)
  ensure
    release << true
    reading&.join
    playing&.join
  end

  it 'can serialize inside an existing monitor and detaches identity strings' do
    snapshot = game.synchronize { serializer.serialize_for_current_player(game) }
    snapshot[:state][:your_id].replace('changed')
    snapshot[:state][:other_players].first[:id].replace('changed')
    ended = game.synchronize { serializer.serialize_game_end(game, alice) }
    ended[:winner].replace('changed')

    expect(alice.identity.id).to eq('Alice')
    expect(bob.identity.id).to eq('Bob')
  end
end
