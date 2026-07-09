#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'smarter_agent'
require_relative 'smart_agent'

# Extends the strongest hand-written baseline with a few focused tactics for
# two-player games.
class CrushingDecider < ActionDecider
  def decide
    return super unless @playable_cards.any?
    return super if @state['already_picked']

    skip = @playable_cards.find { |card| skip?(card) }
    return play(skip) if skip

    pressure_card = uno_pressure_card
    return play(pressure_card) if pressure_card

    double_card = best_double_play
    return double_play(double_card) if double_card

    SmartAgent.new.send(:decide_action, @state)
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
