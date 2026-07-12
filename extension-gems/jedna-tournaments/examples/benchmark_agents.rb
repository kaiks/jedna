#!/usr/bin/env ruby
# frozen_string_literal: true

require 'jedna'
require_relative 'simple_agent'
require_relative 'crushing_agent'

# Fast, deterministic head-to-head harness for the bundled Ruby agents.
class InProcessAgentBenchmark
  POLICIES = {
    'simple' => ->(state) { SimpleAgent.new.send(:decide_action, state) },
    'crushing' => ->(state) { CrushingDecider.new(state).decide }
  }.freeze

  def initialize(first_name, second_name, games:, seed: 12_345)
    @names = [first_name, second_name]
    @policies = @names.to_h { |name| [name, POLICIES.fetch(name)] }
    @games = games
    @seed = seed
    @serializer = Jedna::GameStateSerializer.new
  end

  def run
    wins = @names.to_h { |name| [name, 0] }
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @games.times do |index|
      winner = play_game(index)
      wins[winner] += 1
    end
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    [wins, duration]
  end

  private

  def play_game(index)
    game = build_game(index)
    play_until_finished(game, index)

    game.players[0].identity.id
  end

  def build_game(index)
    srand(@seed + index)
    game = Jedna::Game.new(
      'benchmark',
      1,
      Jedna::NullNotifier.new,
      Jedna::TextRenderer.new,
      Jedna::NullRepository.new
    )
    players = @names.map do |name|
      Jedna::Player.new(Jedna::SimpleIdentity.new(name))
    end
    players.each { |player| game.add_player(player) }

    game.start_game(nil, @names[index % 2])
    game
  end

  def play_until_finished(game, index)
    10_000.times do
      return unless game.started?

      player = game.players[0]
      take_turn(game, player, @policies.fetch(player.identity.id))
    end

    hands = game.players.to_h { |player| [player.identity.id, player.hand.map(&:to_s)] }
    raise "game #{index} exceeded turn limit: top=#{game.top_card} hands=#{hands}"
  end

  def take_turn(game, player, policy)
    state = protocol_state(game)
    action = policy.call(state)
    result = execute_action(game, player, action)
    return recover_turn(game) if result.error?

    draw_and_follow_up(game, player, policy) if action['action'] == 'draw'
  rescue StandardError
    recover_turn(game)
  end

  def draw_and_follow_up(game, player, policy)
    return unless game.started?
    return game.turn_pass unless game.already_picked

    state = protocol_state(game)
    action = policy.call(state)
    result = execute_action(game, player, action)
    game.turn_pass if result.error? && game.started?
  end

  def execute_action(game, player, action)
    Jedna::ActionExecutor.new(game).execute(action, player: player)
  end

  def recover_turn(game)
    return unless game.started?

    game.pick_single unless game.already_picked
    game.turn_pass if game.started?
  end

  def protocol_state(game)
    serialized = @serializer.serialize_for_current_player(game)[:state]
    JSON.parse(JSON.generate(serialized))
  end
end

if $PROGRAM_NAME == __FILE__
  first_name = ARGV.fetch(0)
  second_name = ARGV.fetch(1)
  games = Integer(ARGV.fetch(2, '1000'))
  benchmark = InProcessAgentBenchmark.new(first_name, second_name, games: games)
  wins, duration = benchmark.run

  puts [
    "#{first_name}=#{wins[first_name]}",
    "#{second_name}=#{wins[second_name]}",
    "games=#{games}",
    "duration=#{duration.round(2)}s"
  ].join(' ')
end
