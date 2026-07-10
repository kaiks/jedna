#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'crushing_agent/baseline_strategy'

# Best known hand-written Jedna strategy for two-player games.
class CrushingDecider
  COLORS = {
    'r' => 'red',
    'g' => 'green',
    'b' => 'blue',
    'y' => 'yellow'
  }.freeze

  def initialize(state)
    @state = state
    @hand = state['hand'] || []
    @playable_cards = state['playable_cards'] || []
    @opponent_sizes = (state['other_players'] || []).filter_map do |player|
      player['card_count'] || player[:card_count]
    end
  end

  def decide
    return draw_or_pass unless @playable_cards.any?
    return baseline_decision if @state['already_picked']

    skip = @playable_cards.find { |card| skip?(card) }
    return play(skip) if skip

    pressure_card = uno_pressure_card
    return play(pressure_card) if pressure_card

    double_card = best_double_play
    return double_play(double_card) if double_card

    baseline_decision
  end

  private

  def uno_pressure_card
    return unless (@opponent_sizes.min || 7) == 1

    @playable_cards.find { |card| card == 'wd4' } ||
      @playable_cards.find { |card| draw_two?(card) }
  end

  def best_double_play
    candidates = @playable_cards.reject { |card| wild?(card) }
                                .select { |card| @hand.count(card) >= 2 }

    # With one opponent, a single skip retains the turn while a double skip
    # rotates to the opponent, so preserve the second skip for a later turn.
    candidates.reject! { |card| skip?(card) } if @opponent_sizes.one?

    candidates.max_by { |card| double_play_score(card) }
  end

  def double_play_score(card)
    return 100 if reverse?(card)
    return 90 if draw_two?(card)
    return 30 + figure(card).to_i if number?(card)

    0
  end

  def double_play(card)
    play(card).merge('double_play' => true)
  end

  def baseline_decision
    CrushingBaselineStrategy.new.decide(@state)
  end

  def draw_or_pass
    action = @state['available_actions']&.include?('draw') ? 'draw' : 'pass'
    { 'action' => action }
  end

  def play(card)
    action = { 'action' => 'play', 'card' => card }
    return action unless wild?(card)

    color_counts = @hand.filter_map { |hand_card| COLORS[hand_card[0]] }.tally
    action['wild_color'] = color_counts.max_by { |_, count| count }&.first || 'red'
    action
  end

  def figure(card)
    card[1..]
  end

  def number?(card)
    card.match?(/\A[rbgy][0-9]\z/)
  end

  def reverse?(card)
    card.end_with?('r')
  end

  def skip?(card)
    card.end_with?('s')
  end

  def draw_two?(card)
    card.end_with?('+2')
  end

  def wild?(card)
    %w[w wd4].include?(card)
  end
end

# JSON-lines process wrapper for CrushingDecider.
class CrushingAgent
  def run
    while (line = $stdin.gets)
      data = JSON.parse(line)

      case data['type']
      when 'request_action'
        puts JSON.generate(CrushingDecider.new(data['state']).decide)
        $stdout.flush
      when 'game_end'
        break
      end
    end
  end
end

CrushingAgent.new.run if $PROGRAM_NAME == __FILE__
