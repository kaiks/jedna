# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Jedna::Game, 'state integrity' do
  let(:game) { TestJednaGame.new('creator', 1) }
  let(:alice) { Jedna::Player.new('Alice') }
  let(:bob) { Jedna::Player.new('Bob') }

  before do
    game.add_player(alice)
    game.add_player(bob)
    game.start_game(Jedna::CardStack.new.fill, 'Alice')
    alice.hand = Jedna::Hand.new(%w[r5 b1].map { |code| Jedna::Card.parse(code) })
  end

  def state_of(game)
    [game.game_state, game.players.dup, game.top_card.to_s, game.stacked_cards,
     game.already_picked, game.picked_card, game.card_stack.map(&:object_id),
     game.players.map { |player| player.hand.map { |card| [card.object_id, card.to_s] } }]
  end

  it 'rejects an absent card without changing the game' do
    before = state_of(game)

    expect(game.player_card_play(alice, Jedna::Card.parse('r9'))).to be(false)
    expect(state_of(game)).to eq(before)
  end

  it 'requires the actual card in the hand, even for a matching value' do
    expect(game.player_card_play(alice, Jedna::Card.parse('r5'))).to be(false)
    expect(alice.hand.map(&:to_s)).to eq(%w[r5 b1])
  end

  it 'rejects a different player object with the same identity' do
    impostor = Jedna::Player.new('Alice')
    impostor.hand << Jedna::Card.parse('r9')
    before = state_of(game)

    expect(game.player_card_play(impostor, impostor.hand.first)).to be(false)
    expect(state_of(game)).to eq(before)
  end

  it 'rejects an unavailable double play before playing either card' do
    before = state_of(game)

    expect(game.player_card_play(alice, alice.hand.first, true)).to be(false)
    expect(state_of(game)).to eq(before)
  end

  it 'rejects a non-boolean double-play flag without changing the game' do
    before = state_of(game)

    expect(game.player_card_play(alice, alice.hand.first, 'false')).to be(false)
    expect(state_of(game)).to eq(before)
  end

  it 'does not recolor an out-of-turn wild or raise for a nil card' do
    wild = Jedna::Card.parse('wg')
    bob.hand << wild

    expect(game.player_card_play(bob, wild)).to be(false)
    expect(wild.to_s).to eq('wg')
    expect(game.player_card_play(bob, nil)).to be(false)
  end

  it 'removes the drawn physical card when the hand contains a duplicate' do
    existing = alice.hand.first
    drawn = Jedna::Card.parse('r5')
    game.card_stack.unshift(drawn)
    game.pick_single

    expect(game.player_card_play(alice, existing)).to be(false)
    expect(game.player_card_play(alice, drawn)).to be(true)
    expect(game.top_card).to equal(drawn)
    expect(alice.hand.any? { |card| card.equal?(drawn) }).to be(false)
    expect(alice.hand.any? { |card| card.equal?(existing) }).to be(true)
  end

  it 'keeps a normal win terminal and does not deal again' do
    alice.hand = Jedna::Hand.new([alice.hand.first])
    ended = 0
    game.on_game_ended { ended += 1 }
    game.player_card_play(alice, alice.hand.first)
    before = state_of(game)

    game.pick_single
    game.turn_pass
    game.next_turn
    game.give_cards_to_player(bob, 2)
    game.finish_game
    game.start_game(nil, 'Bob')
    game.player_card_play(bob, bob.hand.first)

    expect(game).to be_finished
    expect(game).not_to be_started
    expect(state_of(game)).to eq(before)
    expect(game.first_player).to eq('Alice')
    expect(ended).to eq(1)
  end

  it 'keeps an instant loss terminal with no pending draw' do
    alice.hand = Jedna::Hand.new(Array.new(35) { Jedna::Card.parse('r5') })
    game.pick_single

    expect(game).to be_finished
    expect(game).not_to be_started
    expect(game.picked_card).to be_nil
    expect(game.already_picked).to be(false)
    expect(game.stacked_cards).to eq(0)
    expect(game.start_game).to be(false)
  end

  it 'cancels a match idempotently without awarding a victory' do
    ended = 0
    game.on_game_ended { ended += 1 }
    game.pick_single

    expect(game.stop_game('Alice')).to be(true)
    expect(game.end_game('Alice')).to be(false)
    expect(game).to be_finished
    expect(game).not_to be_started
    expect(game.picked_card).to be_nil
    expect(game.already_picked).to be(false)
    expect(ended).to eq(0)
  end

  it 'cancels when fewer than two players remain and safely serializes an empty game' do
    game.remove_player(alice)
    expect(game).to be_finished
    game.remove_player(bob)

    expect(game.players).to be_empty
    expect(Jedna::GameStateSerializer.new.serialize_for_current_player(game)).to be_nil
  end

  it 'rejects actions before the match starts and cannot reopen a cancelled lobby' do
    waiting = TestJednaGame.new('creator', 1)
    waiting.add_player(Jedna::Player.new('A'))
    waiting.add_player(Jedna::Player.new('B'))

    expect(waiting.pick_single).to be(false)
    expect(waiting.turn_pass).to be(false)
    expect(waiting.end_game('A')).to be(true)
    expect(waiting.start_game).to be(false)
    expect(waiting.players.map(&:hand)).to all(be_empty)
  end

  it 'preserves normal matching rules during a war after Reverse' do
    alice.hand = Jedna::Hand.new(%w[r+2 b1].map { |code| Jedna::Card.parse(code) })
    bob.hand = Jedna::Hand.new(%w[rr y1].map { |code| Jedna::Card.parse(code) })
    game.player_card_play(alice, alice.hand.first)
    game.player_card_play(bob, bob.hand.first)

    expect(game.playable_now?(Jedna::Card.parse('b+2'))).to be(false)
    expect(game.playable_now?(Jedna::Card.parse('br'))).to be(true)
    expect(game.playable_now?(Jedna::Card.parse('r+2'))).to be(true)
  end

  it 'preserves the extra turn granted by a double Reverse' do
    alice.hand = Jedna::Hand.new(%w[rr rr b1].map { |code| Jedna::Card.parse(code) })

    expect(game.player_card_play(alice, alice.hand.first, true)).to be(true)
    expect(game.players.first).to equal(alice)
    expect(alice.hand.map(&:to_s)).to eq(['b1'])
  end

  it 'preserves the full multiplayer order after a double Reverse' do
    multiplayer = create_game_with_players(%w[Alice Bob Charlie])
    multiplayer.start_game(Jedna::CardStack.new.fill, 'Alice')
    order = multiplayer.players.dup
    player = order.first
    player.hand = Jedna::Hand.new(%w[rr rr b1].map { |code| Jedna::Card.parse(code) })

    multiplayer.player_card_play(player, player.hand.first, true)

    expect(multiplayer.players).to eq(order)
  end

  it 'passes a double Reverse to the opponent under the optional two-player rule' do
    optional = TestJednaGame.new('creator', 1, two_player_reverse_acts_as_skip: true)
    %w[A B].each { |id| optional.add_player(Jedna::Player.new(id)) }
    optional.start_game(Jedna::CardStack.new.fill, 'A')
    player = optional.players.first
    player.hand = Jedna::Hand.new(%w[rr rr b1].map { |code| Jedna::Card.parse(code) })

    optional.player_card_play(player, player.hand.first, true)

    expect(optional.players.first.identity.id).to eq('B')
  end
end

RSpec.describe Jedna::Game, 'stable identity routing' do
  let(:notifier) { Jedna::NullNotifier.new }
  let(:repository) do
    instance_spy(Jedna::NullRepository, create_game: 123, get_player_stats: { total_score: 30, games: 1 })
  end
  let(:game) { Jedna::Game.new('creator', 0, notifier, nil, repository) }
  let(:alice) { Jedna::Player.new(Jedna::UuidIdentity.new('uuid-a', 'Sam')) }
  let(:bob) { Jedna::Player.new(Jedna::UuidIdentity.new('uuid-b', 'Sam')) }

  before do
    game.add_player(alice)
    game.add_player(bob)
    game.start_game(Jedna::CardStack.new.fill, 'uuid-a')
  end

  it 'routes private hands and records joins and deals by ID' do
    game.show_player_cards(bob)

    expect(notifier.player_notifications.map { |entry| entry[:player_id] }).to include('uuid-a', 'uuid-b')
    expect(repository).to have_received(:record_player_join).with(123, 'uuid-a')
    expect(repository).to have_received(:record_player_join).with(123, 'uuid-b')
    expect(repository).to have_received(:save_card_action).with(123, anything, 'uuid-a', true).exactly(7).times
    expect(repository).to have_received(:save_card_action).with(123, anything, 'uuid-b', true).exactly(7).times
  end

  it 'keeps draw, play, winner and statistics keys stable after a rename' do
    game.rename_player('uuid-a', 'Renamed')
    game.pick_single
    game.turn_pass
    game.pick_single
    game.turn_pass
    alice.hand = Jedna::Hand.new([Jedna::Card.parse('r5')])
    game.player_card_play(alice, alice.hand.first)

    expect(repository).to have_received(:save_card_action).with(123, anything, 'uuid-a', true).exactly(8).times
    expect(repository).to have_received(:save_card_action).with(123, anything, 'uuid-a', false)
    expect(repository).to have_received(:update_player_stats).with('uuid-a', true, anything)
    expect(repository).to have_received(:update_player_stats).with('uuid-b', false, 0)
    expect(repository).to have_received(:update_game_ended).with(123, 'uuid-a', anything, anything, 2, 1)
    expect(notifier.game_notifications.last).to start_with('Renamed gains')
  end

  it 'records cancellation only once using the supplied player identity' do
    game.stop_game(alice)
    game.stop_game(alice)

    expect(repository).to have_received(:record_game_stopped).with(123, 'uuid-a').once
    expect(repository).not_to have_received(:update_player_stats)
  end
end
