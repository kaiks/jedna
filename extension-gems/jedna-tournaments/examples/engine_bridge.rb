#!/usr/bin/env ruby
# frozen_string_literal: true

# Engine bridge: runs a single Jedna game where agent1 is controlled via
# stdin/stdout by a Python trainer, and agent2 is an external process agent
# (command provided via ENV['OPPONENT_CMD']).

require 'bundler/setup'
require 'json'
require 'jedna'
require_relative '../lib/jedna_tournaments'

class EngineBridge
  TURN_TIMEOUT = 2.0

  def initialize(opponent_cmd)
    @opponent_cmd = opponent_cmd
    @serializer = Jedna::GameStateSerializer.new
  end

  def run
    opp = JednaTournaments::ProcessAgent.new(@opponent_cmd, 'Opponent')
    opp.start

    # Use silent notifier and null repository for speed/noise-free I/O
    game = Jedna::Game.new('engine_bridge', 1, Jedna::NullNotifier.new, Jedna::TextRenderer.new, Jedna::NullRepository.new)

    p1 = Jedna::Player.new(Jedna::SimpleIdentity.new('agent1'))
    p2 = Jedna::Player.new(Jedna::SimpleIdentity.new('agent2'))
    game.add_player(p1)
    game.add_player(p2)

    game.before_player_turn do |g, current|
      if current.identity.id == 'agent1'
        handle_python_turn(g, current)
      else
        handle_process_turn(g, current, opp)
      end
    end

    winner_id = nil
    scores = {}

    game.on_game_ended do
      # The game keeps the winner at index 0, but compute explicitly to avoid relying on order.
      winner_player = game.players.min_by { |pl| pl.hand.value }
      winner_id = winner_player.identity.id
      game.players.each { |pl| scores[pl.identity.id] = pl.hand.value }
      safe_write(type: 'game_end', winner: winner_id, scores: scores)
    end

    game.start_game

    # Wait until end; the callbacks drive the game
    sleep 0.05 while winner_id.nil?
  ensure
    begin
      opp&.stop
    rescue StandardError
      nil
    end
  end

  private

  def handle_python_turn(game, player)
    state = @serializer.serialize_for_current_player(game)
    safe_write(type: 'request_action', player: 'agent1', state: state[:state])

    action = safe_read
    return game.turn_pass unless action

    case action['action']
    when 'play'
      card = find_card_in_hand(player.hand, action['card'])
      if card
        card.set_wild_color(action['wild_color'].to_sym) if action['wild_color']
        game.player_card_play(player, card, action['double_play'] == true)
      else
        game.turn_pass
      end
    when 'draw'
      game.pick_single
      if game.instance_variable_get(:@already_picked)
        # Ask again after draw if the drawn card is playable
        new_state = @serializer.serialize_for_current_player(game)
        safe_write(type: 'request_action', player: 'agent1', state: new_state[:state])
        follow = safe_read
        if follow && follow['action'] == 'play'
          card = find_card_in_hand(player.hand, follow['card'])
          if card
            card.set_wild_color(follow['wild_color'].to_sym) if follow['wild_color']
            game.player_card_play(player, card)
          else
            game.turn_pass
          end
        else
          game.turn_pass
        end
      else
        game.turn_pass
      end
    else
      game.turn_pass
    end
  end

  def handle_process_turn(game, player, agent)
    state = @serializer.serialize_for_current_player(game)
    action = agent.request_action(state[:state], timeout: TURN_TIMEOUT)
    case action['action']
    when 'play'
      card = find_card_in_hand(player.hand, action['card'])
      if card
        card.set_wild_color(action['wild_color'].to_sym) if action['wild_color']
        game.player_card_play(player, card, action['double_play'] == true)
      else
        game.turn_pass
      end
    when 'draw'
      game.pick_single
      if game.instance_variable_get(:@already_picked)
        new_state = @serializer.serialize_for_current_player(game)
        follow = agent.request_action(new_state[:state], timeout: TURN_TIMEOUT)
        if follow['action'] == 'play'
          card = find_card_in_hand(player.hand, follow['card'])
          if card
            card.set_wild_color(follow['wild_color'].to_sym) if follow['wild_color']
            game.player_card_play(player, card)
          else
            game.turn_pass
          end
        else
          game.turn_pass
        end
      else
        game.turn_pass
      end
    else
      game.turn_pass
    end
  rescue StandardError
    game.pick_single unless game.instance_variable_get(:@already_picked)
    game.turn_pass
  end

  def find_card_in_hand(hand, card_string)
    return nil unless card_string
    if %w[w wd4].include?(card_string)
      hand.find do |c|
        (c.figure == 'wild' && card_string == 'w') ||
          (c.figure == 'wild+4' && card_string == 'wd4')
      end
    else
      hand.find { |c| c.to_s == card_string }
    end
  end

  def safe_write(obj)
    STDOUT.write(JSON.generate(obj) + "\n")
    STDOUT.flush
  rescue StandardError
    nil
  end

  def safe_read
    line = STDIN.gets
    return nil unless line
    JSON.parse(line)
  rescue StandardError
    nil
  end
end

opponent_cmd = ENV['OPPONENT_CMD']
if opponent_cmd.nil? || opponent_cmd.empty?
  warn 'OPPONENT_CMD not set'
  exit 1
end

EngineBridge.new(opponent_cmd).run
