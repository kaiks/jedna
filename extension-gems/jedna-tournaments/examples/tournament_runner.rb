#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'jedna'
require 'yaml'
require_relative '../lib/jedna_tournaments'

# Executes one two-player game through the JSON-lines process boundary.
class ArenaGame
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
  ensure
    agents&.each_value { |agent| stop_agent(agent) }
  end

  private

  def start_agents
    agents = {}
    @players.each do |name, command|
      agent = JednaTournaments::ProcessAgent.new(command, name)
      agent.start
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

    case action['action']
    when 'play'
      recover_turn(game) unless play_card(game, player, action)
    when 'draw'
      draw_and_follow_up(game, player, agent)
    when 'pass'
      game.turn_pass
    else
      recover_turn(game)
    end
  rescue StandardError
    recover_turn(game)
  end

  def draw_and_follow_up(game, player, agent)
    game.pick_single
    return unless game.started?
    return game.turn_pass unless game.already_picked

    action = request_action(game, agent)
    played = action['action'] == 'play' && play_card(game, player, action)
    game.turn_pass unless played
  end

  def request_action(game, agent)
    state = @serializer.serialize_for_current_player(game)[:state]
    action = agent.request_action(state, timeout: @turn_timeout)
    return action if action.is_a?(Hash) && action['action']

    raise "invalid action: #{action.inspect}"
  end

  def play_card(game, player, action)
    card = find_card(player.hand, action['card'])
    return false unless card

    if card.wild?
      return false unless action['wild_color']

      card.set_wild_color(action['wild_color'].to_sym)
    end

    game.player_card_play(player, card, action['double_play'] == true)
  end

  def find_card(hand, encoded_card)
    case encoded_card
    when 'w'
      hand.find { |card| card.figure == 'wild' }
    when 'wd4'
      hand.find { |card| card.figure == 'wild+4' }
    else
      hand.find { |card| card.to_s == encoded_card }
    end
  end

  def recover_turn(game)
    return unless game.started?

    game.pick_single unless game.already_picked
    game.turn_pass if game.started?
  end

  def finish_game(game, agents)
    winner = game.players.first.identity.id
    scores = game.players.to_h { |player| [player.identity.id, player.hand.value] }
    agents.each_value { |agent| notify_agent(agent, winner, scores) }
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
  attr_reader :results

  def initialize(config_file)
    config = YAML.safe_load_file(config_file)
    @agents = config.fetch('agents')
    @games_per_round = Integer(config.fetch('games_per_round', 10))
    @turn_timeout = timeout_value(config.dig('timeouts', 'turn_timeout'), 10.0)
    @game_timeout = timeout_value(config.dig('timeouts', 'game_timeout'), 15.0)
    @stdout = config.dig('output', 'stdout') != false
    @results = @agents.to_h { |name, _command| [name, 0] }
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
    ArenaGame.new(
      players,
      turn_timeout: @turn_timeout,
      game_timeout: @game_timeout
    ).play
  rescue StandardError => e
    warn "Arena game failed: #{e.message}"
    nil
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
