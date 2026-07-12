#!/usr/bin/env ruby
# frozen_string_literal: true

# Engine bridge: runs a single Jedna game where agent1 is controlled via
# stdin/stdout by a Python trainer, and agent2 is an external process agent
# (command provided via ENV['OPPONENT_CMD']).

require 'bundler/setup'
require 'json'
require 'jedna'
require_relative '../lib/jedna_tournaments'

srand(Integer(ENV['JEDNA_SEED'])) if ENV['JEDNA_SEED']

# Runs the game engine for a Python-controlled player and process opponent.
class EngineBridge
  TURN_TIMEOUT = 10.0

  class Shutdown < StandardError; end

  def initialize(opponent_cmd, persistent: false)
    @opponent_cmd = opponent_cmd
    @persistent = persistent
    @serializer = Jedna::GameStateSerializer.new
  end

  def run
    opp = JednaTournaments::ProcessAgent.new(@opponent_cmd, 'Opponent')
    opp.start
    @persistent ? run_persistent(opp) : run_game(opp)
  rescue Shutdown
    nil
  ensure
    stop_agent(opp)
  end

  private

  def run_persistent(opponent)
    while (reset = next_reset)
      srand(Integer(reset['seed'])) if reset['seed']
      opponent.notify(type: 'game_reset')
      run_game(opponent)
    end
  end

  def next_reset
    message = safe_read
    return nil unless message

    raise Shutdown if message['type'] == 'shutdown'
    raise ArgumentError, "expected reset message, got: #{message.inspect}" unless message['type'] == 'reset'

    message
  end

  def run_game(opponent)
    # Use silent notifier and null repository for speed/noise-free I/O
    game = Jedna::Game.new('engine_bridge', 1, Jedna::NullNotifier.new, Jedna::TextRenderer.new, Jedna::NullRepository.new)

    p1 = Jedna::Player.new(Jedna::SimpleIdentity.new('agent1'))
    p2 = Jedna::Player.new(Jedna::SimpleIdentity.new('agent2'))
    game.add_player(p1)
    game.add_player(p2)

    winner_id = nil
    scores = {}

    game.on_game_ended do
      # The game keeps the winner at index 0, but compute explicitly to avoid relying on order.
      winner_player = game.players.min_by { |pl| pl.hand.value }
      winner_id = winner_player.identity.id
      game.players.each { |pl| scores[pl.identity.id] = pl.hand.value }
      card_counts = game.players.to_h { |player| [player.identity.id, player.hand.size] }
      safe_write(type: 'game_end', winner: winner_id, scores: scores, card_counts: card_counts)
    end

    game.start_game

    until winner_id
      current_player = game.players[0]
      if current_player.identity.id == 'agent1'
        handle_python_turn(game, current_player)
      else
        handle_process_turn(game, current_player, opponent)
      end
    end
  end

  def handle_python_turn(game, player)
    action = request_python_action(game)
    return recover_turn(game) unless action

    result = execute_action(game, player, action)
    return recover_turn(game) if result.error?

    finish_draw(game, player, request_python_action(game)) if action['action'] == 'draw'
  end

  def handle_process_turn(game, player, agent)
    state = @serializer.serialize_for_current_player(game)
    action = agent.request_action(state[:state], timeout: TURN_TIMEOUT)
    result = execute_action(game, player, action)
    return recover_turn(game) if result.error?

    finish_draw(game, player, request_process_action(game, agent)) if action['action'] == 'draw'
  rescue StandardError
    recover_turn(game)
  end

  def request_python_action(game)
    return unless game.started?

    state = @serializer.serialize_for_current_player(game)
    safe_write(state.merge(player: 'agent1'))
    read_python_action
  end

  def request_process_action(game, agent)
    return unless game.started?
    return unless game.already_picked

    state = @serializer.serialize_for_current_player(game)
    agent.request_action(state[:state], timeout: TURN_TIMEOUT)
  end

  def finish_draw(game, player, action)
    return unless game.started?
    return game.turn_pass unless game.already_picked && action

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

  def safe_write(obj)
    $stdout.write("#{JSON.generate(obj)}\n")
    $stdout.flush
  rescue StandardError
    nil
  end

  def safe_read
    line = $stdin.gets
    return nil unless line

    JSON.parse(line)
  rescue StandardError
    nil
  end

  def read_python_action
    message = safe_read
    raise Shutdown if message&.fetch('type', nil) == 'shutdown'

    message
  end

  def stop_agent(agent)
    agent&.stop
  rescue StandardError
    nil
  end
end

opponent_cmd = ENV.fetch('OPPONENT_CMD', nil)
if opponent_cmd.nil? || opponent_cmd.empty?
  warn 'OPPONENT_CMD not set'
  exit 1
end

persistent = ARGV.delete('--persistent')
EngineBridge.new(opponent_cmd, persistent: persistent).run
