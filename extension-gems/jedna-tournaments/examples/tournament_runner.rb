#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'jedna'
require 'yaml'
require_relative '../lib/jedna_tournaments'

# Executes one two-player game through the JSON-lines process boundary.
class ArenaGame
  # Only failures attributed to an agent forfeit a match.
  class Forfeit < StandardError
    attr_reader :player_id, :reason

    def initialize(player_id, reason, message)
      @player_id = player_id
      @reason = reason
      super(message)
    end
  end

  attr_reader :outcome

  def initialize(players, turn_timeout:, game_timeout:)
    @players = players
    @turn_timeout = turn_timeout
    @game_timeout = game_timeout
    @serializer = Jedna::GameStateSerializer.new
  end

  def play
    agents = start_agents
    game = build_game
    game.start_game(nil, @players.first.first)
    play_turns(game, agents)
    finish_game(game, agents)
  rescue Forfeit => e
    game&.stop_game(e.player_id)
    winner = (@players.keys - [e.player_id]).fetch(0)
    @outcome = { winner: winner, reason: e.reason, loser: e.player_id, message: e.message }
    agents&.each_value { |agent| notify_agent(agent, winner, {}) }
    winner
  ensure
    agents&.each_value { |agent| stop_agent(agent) }
  end

  private

  def start_agents
    agents = {}
    @players.each do |name, command|
      agent = JednaTournaments::ProcessAgent.new(command, name)
      agent_request(name) { agent.start }
      agents[name] = agent
    end
    agents
  rescue StandardError
    agents.each_value { |agent| stop_agent(agent) }
    raise
  end

  def build_game
    game = Jedna::Game.new(
      'arena',
      1,
      Jedna::NullNotifier.new,
      Jedna::TextRenderer.new,
      Jedna::NullRepository.new
    )
    @players.each_key do |name|
      game.add_player(Jedna::Player.new(Jedna::SimpleIdentity.new(name)))
    end
    game
  end

  def play_turns(game, agents)
    deadline = monotonic_time + @game_timeout if @game_timeout
    while game.started?
      raise "game exceeded #{@game_timeout}s timeout" if deadline && monotonic_time >= deadline

      player = game.players.first
      take_turn(game, player, agents.fetch(player.identity.id))
    end
  end

  def take_turn(game, player, agent)
    action = request_action(game, agent)
    result = execute_action(game, player, action)
    raise Forfeit.new(player.identity.id, :invalid_action, result.message) if result.error?

    draw_and_follow_up(game, player, agent) if action['action'] == 'draw'
  end

  def draw_and_follow_up(game, player, agent)
    return unless game.started? && game.already_picked

    action = request_action(game, agent)
    result = execute_action(game, player, action)
    raise Forfeit.new(player.identity.id, :invalid_action, result.message) if result.error?
  end

  def request_action(game, agent)
    state = @serializer.serialize_for_current_player(game)[:state]
    action = agent_request(state[:your_id]) { agent.request_action(state, timeout: @turn_timeout) }
    return action if action.is_a?(Hash) && action['action']

    raise Forfeit.new(state[:your_id], :invalid_action, "invalid action: #{action.inspect}")
  end

  def execute_action(game, player, action)
    Jedna::ActionExecutor.new(game).execute(action, player: player)
  end

  def agent_request(player_id)
    yield
  rescue JednaTournaments::TimeoutError => e
    raise Forfeit.new(player_id, :timeout, e.message)
  rescue JednaTournaments::AgentError => e
    raise Forfeit.new(player_id, :agent_error, e.message)
  end

  def finish_game(game, agents)
    winner = game.players.first.identity.id
    scores = game.players.to_h { |player| [player.identity.id, player.hand.value] }
    agents.each_value { |agent| notify_agent(agent, winner, scores) }
    @outcome = { winner: winner, reason: :game_end, scores: scores }
    winner
  end

  def notify_agent(agent, winner, scores)
    agent.notify_game_end(winner, scores)
  rescue StandardError
    nil
  end

  def stop_agent(agent)
    agent.stop
  rescue StandardError
    nil
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

# Loads an arena YAML file and runs every pair of agents against each other.
class ConfiguredTournamentRunner
  attr_reader :results, :outcomes

  def initialize(config_file)
    config = YAML.safe_load_file(config_file)
    @agents = config.fetch('agents')
    @games_per_round = Integer(config.fetch('games_per_round', 10))
    @turn_timeout = timeout_value(config.dig('timeouts', 'turn_timeout'), 10.0)
    @game_timeout = timeout_value(config.dig('timeouts', 'game_timeout'), 15.0)
    @stdout = config.dig('output', 'stdout') != false
    @results = @agents.to_h { |name, _command| [name, 0] }
    @outcomes = []
    validate!
  end

  def run
    @agents.keys.combination(2) { |first, second| run_match(first, second) }
    print_results
    @results
  end

  private

  def validate!
    raise 'At least 2 agents required' if @agents.size < 2
    raise 'games_per_round must be positive' unless @games_per_round.positive?

    @agents.each do |name, command|
      raise "Agent #{name} has no command" unless command.is_a?(String) && !command.empty?
    end
  end

  def run_match(first, second)
    wins = { first => 0, second => 0 }
    @games_per_round.times do |game_index|
      order = game_index.even? ? [first, second] : [second, first]
      winner = play_game(order)
      next unless winner

      wins[winner] += 1
      @results[winner] += 1
      print '.' if @stdout
    end
    puts " #{first}=#{wins[first]} #{second}=#{wins[second]}" if @stdout
  end

  def play_game(order)
    players = order.to_h { |name| [name, @agents.fetch(name)] }
    arena = ArenaGame.new(
      players,
      turn_timeout: @turn_timeout,
      game_timeout: @game_timeout
    )
    winner = arena.play
    @outcomes << arena.outcome
    winner
  end

  def print_results
    return unless @stdout

    puts 'Final wins:'
    @results.sort_by { |_name, wins| -wins }.each do |name, wins|
      puts "  #{name}: #{wins}"
    end
  end

  def timeout_value(value, default)
    timeout = value.nil? ? default : Float(value)
    raise 'timeouts must be positive' unless timeout.positive?

    timeout
  end
end

if $PROGRAM_NAME == __FILE__
  config_file = ARGV.first
  abort "Usage: #{$PROGRAM_NAME} <config.yaml>" unless config_file

  ConfiguredTournamentRunner.new(config_file).run
end
