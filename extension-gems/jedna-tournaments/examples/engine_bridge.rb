#!/usr/bin/env ruby
# frozen_string_literal: true

# Engine bridge: runs Jedna games where agent1 is controlled via stdin/stdout
# by a Python trainer and 1-9 seats use external process agents.

require 'bundler/setup'
require 'json'
require 'jedna'
require_relative '../lib/jedna_tournaments'

srand(Integer(ENV['JEDNA_SEED'])) if ENV['JEDNA_SEED']

# Runs the game engine for a Python-controlled player and process opponent.
class EngineBridge
  TURN_TIMEOUT = 10.0
  PLAYER_RANGE = (2..10)

  class Shutdown < StandardError; end

  def initialize(opponent_cmd, persistent: false, player_count: 2, max_player_count: player_count)
    @opponent_cmd = opponent_cmd
    @persistent = persistent
    @initial_player_count = validate_player_count(player_count)
    @max_player_count = validate_player_count(max_player_count)
    @serializer = Jedna::GameStateSerializer.new
    @opponents = {}
  end

  def run
    if @persistent
      ensure_opponents(@max_player_count)
      run_persistent
    else
      ensure_opponents(@initial_player_count)
      run_game(@initial_player_count)
    end
  rescue Shutdown
    nil
  ensure
    stop_all_opponents
  end

  private

  def run_persistent
    while (reset = next_reset)
      srand(Integer(reset['seed'])) if reset['seed']
      player_count = validate_player_count(reset.fetch('player_count', @initial_player_count))
      ensure_opponents(player_count)
      (2..player_count).map { |index| @opponents.fetch("agent#{index}") }
                       .each { |opponent| opponent.notify(type: 'game_reset') }
      run_game(player_count)
    end
  end

  def next_reset
    message = safe_read
    return nil unless message

    raise Shutdown if message['type'] == 'shutdown'
    raise ArgumentError, "expected reset message, got: #{message.inspect}" unless message['type'] == 'reset'

    message
  end

  def run_game(player_count)
    # Use silent notifier and null repository for speed/noise-free I/O
    game = Jedna::Game.new('engine_bridge', 1, Jedna::NullNotifier.new, Jedna::TextRenderer.new, Jedna::NullRepository.new)

    player_count.times do |index|
      player_id = "agent#{index + 1}"
      game.add_player(Jedna::Player.new(Jedna::SimpleIdentity.new(player_id)))
    end

    winner_id = nil
    scores = {}

    game.on_game_ended do
      winner_id = game.players.first.identity.id
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
        handle_process_turn(game, current_player, @opponents.fetch(current_player.identity.id))
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

  def validate_player_count(value)
    player_count = Integer(value)
    return player_count if PLAYER_RANGE.cover?(player_count)

    raise ArgumentError, "player_count must be between #{PLAYER_RANGE.begin} and #{PLAYER_RANGE.end}"
  end

  def ensure_opponents(player_count)
    desired_ids = (2..player_count).map { |index| "agent#{index}" }
    (desired_ids - @opponents.keys).each do |player_id|
      opponent = JednaTournaments::ProcessAgent.new(@opponent_cmd, player_id)
      opponent.start
      @opponents[player_id] = opponent
    end
  end

  def stop_all_opponents
    @opponents.each_value { |opponent| stop_agent(opponent) }
    @opponents.clear
  end
end

opponent_cmd = ENV.fetch('OPPONENT_CMD', nil)
if opponent_cmd.nil? || opponent_cmd.empty?
  warn 'OPPONENT_CMD not set'
  exit 1
end

persistent = ARGV.delete('--persistent')
player_count = Integer(ENV.fetch('PLAYER_COUNT', 2))
max_player_count = Integer(ENV.fetch('MAX_PLAYER_COUNT', player_count))
EngineBridge.new(
  opponent_cmd,
  persistent: persistent,
  player_count: player_count,
  max_player_count: max_player_count
).run
