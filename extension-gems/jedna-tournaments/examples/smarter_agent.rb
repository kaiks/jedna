#!/usr/bin/env ruby
# frozen_string_literal: true

# SmarterAgent – refactored for clarity & maintainability
# -------------------------------------------------------
# Major design changes:
#  • Logic decomposed into small, intention‑revealing methods.
#  • Card helpers extracted to the CardUtil module.
#  • Decision flow split into dedicated “steps” inside ActionDecider.
#  • Pure functions & constants replace magic literals.
#  • Inline documentation and yard‑style comments ease onboarding.
#
# Behaviour is functionally identical to the original script.
# -------------------------------------------------------

require 'json'

# Utility helpers for working with Jedna/UNO cards.
module CardUtil
  COLORS          = %w[r b g y].freeze
  WILD_CARDS      = %w[w wd4].freeze
  NUMBER_REGEX    = /^[rbgy][0-9]$/
  REVERSE_SUFFIX  = 'r'
  SKIP_SUFFIX     = 's'
  DRAW_TWO_SUFFIX = '+2'

  module_function

  # @param card [String]
  # @return [String] single‑letter colour (or "w" for wild)
  def color(card)
    card[0]
  end

  # @param card [String]
  # @return [String] everything after the colour letter (e.g. "3", "+2", "r")
  def figure(card)
    card[1..]
  end

  # @param card [String]
  # @return [Boolean]
  def number?(card)
    card.match?(NUMBER_REGEX)
  end

  # @param card [String]
  # @return [Boolean]
  def reverse?(card)
    card.end_with?(REVERSE_SUFFIX)
  end

  def skip?(card)
    card.end_with?(SKIP_SUFFIX)
  end

  def draw_two?(card)
    card.end_with?(DRAW_TWO_SUFFIX)
  end

  def wild?(card)
    WILD_CARDS.include?(card)
  end

  # Translate colour letter to full name expected by engine.
  # @param letter [String] "r", "g", "b", "y"
  # @return [String] colour name
  def full_color(letter)
    {
      'r' => 'red',
      'g' => 'green',
      'b' => 'blue',
      'y' => 'yellow'
    }.fetch(letter, 'red')
  end
end

# Calculates best action for a given game state.
class ActionDecider
  include CardUtil

  def initialize(state)
    @state            = state
    @playable_cards   = state['playable_cards'] || []
    @hand             = state['hand'] || []
    @opponent_sizes   = state['opponent_hand_sizes'] || []
    @war_cards        = state['war_cards_to_draw'] || 0
    @top_card         = state['top_card']
  end

  # @return [Hash] JSON‑serialisable action (draw / pass / play)
  def decide
    return draw_action unless @playable_cards.any?

    # Ordered decision pipeline – early‑return style for readability.
    handle_war ||
      disrupt_if_uno      ||
      play_safe_endgame   ||
      execute_skip_chain  ||
      smart_default_play  ||
      wildcard_or_fallback
  end

  private

  ## Decision steps ---------------------------------------------------------

  def handle_war
    return unless @war_cards.positive? && @top_card

    # 1) Try reversing the war.
    reverse = @playable_cards.find { |c| reverse?(c) && color(c) == color(@top_card) }
    return play(reverse) if reverse

    min_opp = @opponent_sizes.min || 7
    return unless min_opp <= 2 || @hand.size >= 10

    # Prefer draw two if playable, fallback to wd4 if not.
    war_card = @playable_cards.find { |c| draw_two?(c) }
    war_card ||= @playable_cards.find { |c| c == 'wd4' }
    play(war_card) if war_card
  end

  def disrupt_if_uno
    return unless (@opponent_sizes.min || 2) == 1

    disruptive = @playable_cards.find { |c| draw_two?(c) || skip?(c) || reverse?(c) }
    disruptive ||= 'wd4' if @playable_cards.include?('wd4')
    disruptive && play(disruptive)
  end

  def play_safe_endgame
    return unless @hand.size <= 2

    safe = @playable_cards.find { |c| number?(c) }
    safe ||= @playable_cards.find { |c| !wild?(c) }
    play(safe) if safe
  end

  def execute_skip_chain
    skip_cards = @playable_cards.select { |c| skip?(c) }
    many_skips = @hand.count { |c| skip?(c) }

    return unless (@hand.size <= 4 && skip_cards.size >= 2) || many_skips >= 6

    play(skip_cards.first)
  end

  # Main, more nuanced card‑selection logic.
  def smart_default_play
    non_wild = @playable_cards.reject { |c| wild?(c) }
    return if non_wild.empty?

    min_opp = @opponent_sizes.min || 7

    numbers, actions = non_wild.partition { |c| number?(c) }

    # Aggress on opponent UNO.
    return play(actions.first) if min_opp == 1 && actions.any?

    # Prefer isolated numbers when opponents have >= 4 cards.
    if min_opp >= 4 && numbers.any?
      isolated = numbers.find { |card| isolated_number?(card) }
      return play(isolated) if isolated
      return play(numbers.first) if actions.any?
    end

    # Chain evaluation.
    best_chain = best_chain_starter(non_wild)
    return play(best_chain) if best_chain

    # Fallback: number → action.
    play(numbers.first || actions.first)
  end

  def wildcard_or_fallback
    wild = @playable_cards.find { |c| c == 'w' } || @playable_cards.find { |c| c == 'wd4' }
    play(wild) if wild
  end

  ## Helper methods ---------------------------------------------------------

  def draw_action
    if @state['available_actions']&.include?('draw')
      { 'action' => 'draw' }
    else
      { 'action' => 'pass' }
    end
  end

  def play(card)
    return nil unless card

    action = { 'action' => 'play', 'card' => card }

    # Wild needs a colour.
    if wild?(card)
      counts = @hand.map { |c| color(c) }.reject { |c| c == 'w' }.tally
      chosen = counts.max_by { |_, v| v }&.first || 'r'
      action['wild_color'] = full_color(chosen)
    end

    action
  end

  # True if the number appears nowhere else in hand.
  def isolated_number?(card)
    fig = figure(card)
    @hand.none? { |c| c != card && figure(c) == fig }
  end

  # Simple heuristic to find a card that opens up the biggest chain.
  def best_chain_starter(candidates)
    best_card  = nil
    best_score = 0.0

    candidates.each do |card|
      score = chain_score(card)
      next unless score > best_score ||
                  (score == best_score && better_tiebreak?(card, best_card))

      best_score = score
      best_card  = card
    end

    best_score >= 2 ? best_card : nil
  end

  # Tiebreaker when chain scores are equal:
  # - Prefer numbers over action cards
  # - If both numbers, prefer the higher digit (reduces opponent's end-game points)
  # - Otherwise keep existing
  def better_tiebreak?(candidate, incumbent)
    return true if incumbent.nil?

    cand_num = number?(candidate)
    inc_num  = number?(incumbent)

    return true  if cand_num && !inc_num
    return false if !cand_num && inc_num

    if cand_num && inc_num
      cand_val = figure(candidate).to_i
      inc_val  = figure(incumbent).to_i
      return cand_val > inc_val
    end

    false
  end

  # Lightweight version of original calculate_simple_chain_score.
  def chain_score(card)
    clr   = color(card)
    fig   = figure(card)
    rests = @hand - [card]

    score = rests.count { |c| color(c) == clr || figure(c) == fig }

    # Reward if the follow‑ups include variety (colour change opportunities)
    if number?(card)
      alt_colours = rests.select { |c| figure(c) == fig && color(c) != clr }
      score += alt_colours.size * 0.3
    end

    # Slight penalty for using action cards early.
    score -= 0.5 unless number?(card)
    score
  end
end

# --------------------------------------------------------------------------
# Main Agent wrapper (kept thin).
# --------------------------------------------------------------------------
class SmarterAgent
  def run
    until (line = $stdin.gets).nil?
      data = JSON.parse(line)

      case data['type']
      when 'request_action'
        decision = ActionDecider.new(data['state']).decide
        puts JSON.generate(decision)
        $stdout.flush
      when 'game_end'
        break
      end
    end
  end
end

SmarterAgent.new.run if $PROGRAM_NAME == __FILE__
