#!/usr/bin/env ruby
# frozen_string_literal: true

# SmarterAgent – victory‑first decision order
# ------------------------------------------
# Updates (July 2025)
# • New **immediate‑win detection** as the very first check.
# • Strict ordering of decision steps per spec:
#     1) immediate win  2) war‑handling  3) opponent UNO disruption
#     4) smart default  5) wildcard / pass
# • Introduced `allow_wd4?` rule set – the agent now plays **WD4** only if:
#     • an opponent has < 3 cards, OR
#     • the war pile > 4, OR
#     • we have ≤ 3 cards in hand.
# • `play` short‑circuits if WD4 isn’t currently allowed.
# ------------------------------------------

require 'json'

############################################################
# Card utilities                                            #
############################################################
module CardUtil
  COLORS          = %w[r b g y].freeze
  WILD_CARDS      = %w[w wd4].freeze
  NUMBER_REGEX    = /^[rbgy][0-9]$/
  REVERSE_SUFFIX  = 'r'
  SKIP_SUFFIX     = 's'
  DRAW_TWO_SUFFIX = '+2'

  module_function

  def color(card)  = card[0]
  def figure(card) = card[1..]

  def number?(card)  = card.match?(NUMBER_REGEX)
  def reverse?(card) = card.end_with?(REVERSE_SUFFIX)
  def skip?(card)    = card.end_with?(SKIP_SUFFIX)
  def draw_two?(card)= card.end_with?(DRAW_TWO_SUFFIX)
  def wild?(card)    = WILD_CARDS.include?(card)

  def full_color(letter)
    {
      'r' => 'red',  'g' => 'green',
      'b' => 'blue', 'y' => 'yellow'
    }.fetch(letter, 'red')
  end

  # Can +b+ legally follow +a+ ?
  def can_follow?(a, b)
    return true if wild?(b) || wild?(a)

    color(a) == color(b) || figure(a) == figure(b)
  end
end

############################################################
# Exact longest‑chain search (unchanged)                   #
############################################################
module ChainAnalyzer
  extend CardUtil

  module_function

  def longest_chain_start(playable, hand)
    n = hand.size
    return nil if n.zero? || n > 14 || playable.empty?

    adj = Array.new(n) { Array.new(n, false) }
    n.times { |i| n.times { |j| adj[i][j] = can_follow?(hand[i], hand[j]) } }

    size = 1 << n
    dp   = Array.new(size) { Array.new(n, 0) }
    n.times { |i| dp[1 << i][i] = 1 }

    1.upto(size - 1) do |mask|
      n.times do |i|
        len = dp[mask][i]
        next if len.zero?

        n.times do |j|
          next if mask & (1 << j) != 0 || !adj[i][j]

          new_mask = mask | (1 << j)
          dp[new_mask][j] = len + 1 if len + 1 > dp[new_mask][j]
        end
      end
    end

    best_for_card = Hash.new(0)
    (0...size).each do |mask|
      n.times do |i|
        len = dp[mask][i]
        next if len.zero?

        start_idx = Math.log2(mask & -mask).to_i
        start_card = hand[start_idx]
        best_for_card[start_card] = len if len > best_for_card[start_card]
      end
    end

    # Prefer action cards on tie (e.g., skips) to keep control chains
    # Prefer numbers over actions on tie, and if both numbers, prefer higher digit
    playable.max_by { |c| [best_for_card[c], (number?(c) ? 1 : 0), (number?(c) ? figure(c).to_i : -1)] }
  end
end

############################################################
# Decision engine                                          #
############################################################
class ActionDecider
  include CardUtil

  def initialize(state)
    @state          = state
    @playable_cards = state['playable_cards'] || []
    @hand           = state['hand'] || []
    # Derive opponent sizes from other_players.card_count
    @opp_sizes      = (state['other_players'] || []).map { |p| p['card_count'] || p[:card_count] }.compact
    @war_cards      = state['war_cards_to_draw'] || 0
    @top_card       = state['top_card']
  end

  # Primary decision pipeline – victory‑first.
  def decide
    return draw_action if @playable_cards.empty?

    immediate_win      ||
      handle_war       ||
      disrupt_if_uno   ||
      smart_default_play ||
      wildcard_or_pass
  end

  private

  ##########################################################
  # Step 1 — attempt instant victory                       #
  ##########################################################
  def immediate_win
    # 1‑card scenario.
    return play(@hand.first) if @hand.size == 1 && @playable_cards.include?(@hand.first)

    # Skip‑chain scenario (single opponent only).
    return unless @opp_sizes.size == 1

    skips      = @hand.select { |c| skip?(c) }
    non_skips  = @hand - skips

    full_skip_chain = skips.size == @hand.size
    one_off_chain   = skips.size == @hand.size - 1 && non_skips.size == 1 &&
                      skips.any? { |s| color(s) == color(non_skips.first) }

    return unless full_skip_chain || one_off_chain

    start_skip = @playable_cards.find { |c| skip?(c) }
    play(start_skip) if start_skip
  end

  ##########################################################
  # Step 2 — war handling                                  #
  ##########################################################
  def handle_war
    return unless @war_cards.positive? && @top_card

    rev = @playable_cards.find { |c| reverse?(c) && color(c) == color(@top_card) }
    return play(rev) if rev

    min_opp = @opp_sizes.min || 7
    return unless min_opp <= 2 || @hand.size >= 10

    war_card = @playable_cards.find { |c| draw_two?(c) || (c == 'wd4' && allow_wd4?) }
    play(war_card) if war_card
  end

  ##########################################################
  # Step 3 — disrupt opponent at UNO                       #
  ##########################################################
  def disrupt_if_uno
    return unless (@opp_sizes.min || 2) == 1

    disruptive = @playable_cards.find { |c| draw_two?(c) || skip?(c) || reverse?(c) }
    disruptive ||= 'wd4' if @playable_cards.include?('wd4') && allow_wd4?
    play(disruptive) if disruptive
  end

  ##########################################################
  # Step 4 — smart default play (unchanged)                #
  ##########################################################
  def smart_default_play
    non_wild = @playable_cards.reject { |c| wild?(c) }
    return if non_wild.empty?

    min_opp = @opp_sizes.min || 7
    numbers, actions = non_wild.partition { |c| number?(c) }

    # Prefer action aggression when opp at UNO (shouldn’t happen – handled earlier, but safe).
    return play(actions.first) if min_opp == 1 && actions.any?

    # Isolated number preference when we’re ahead.
    if min_opp >= 4 && numbers.any?
      iso = numbers.find { |card| isolated_number?(card) }
      return play(iso) if iso

      # Prefer a playable duplicate to exploit same-turn double play.
      dup_playables = @playable_cards.select { |c| @hand.count(c) > 1 }
      unless dup_playables.empty?
        action_dups = dup_playables.reject { |c| number?(c) }
        chosen_dup = action_dups.first || dup_playables.first
        return play(chosen_dup)
      end

      # Before defaulting to a number, see if chain analysis recommends
      # an opening with strong continuation.
      best_chain = ChainAnalyzer.longest_chain_start(@playable_cards, @hand)
      return play(best_chain) if best_chain

      return play(numbers.first) if actions.any?
    end

    # Exact longest‑chain search.
    best_chain = ChainAnalyzer.longest_chain_start(@playable_cards, @hand)
    return play(best_chain) if best_chain

    # Heuristic fallback.
    heuristic = heuristic_chain_starter(non_wild)
    return play(heuristic) if heuristic

    # Simple fallback.
    play(numbers.first || actions.first)
  end

  ##########################################################
  # Step 5 — wild or pass                                  #
  ##########################################################
  def wildcard_or_pass
    wild = @playable_cards.find { |c| c == 'w' }
    return play(wild) if wild

    if @playable_cards.include?('wd4')
      return play('wd4') if allow_wd4?
      return draw_action if @state['available_actions']&.include?('draw')
      return play('wd4')
    end
    draw_action
  end

  ##########################################################
  # Helpers                                                #
  ##########################################################
  def allow_wd4?
    (@opp_sizes.min || 4) < 3 || @war_cards > 4 || @hand.size <= 3
  end

  def draw_action
    if @state['available_actions']&.include?('draw')
      { 'action' => 'draw' }
    else
      { 'action' => 'pass' }
    end
  end

  def play(card)
    return nil unless card
    return nil if card == 'wd4' && !allow_wd4?

    action = { 'action' => 'play', 'card' => card }
    # Request a same-turn double play if we hold a duplicate of the same card
    action['double_play'] = true if @hand.count(card) > 1
    if wild?(card)
      counts = @hand.map { |c| color(c) }.reject { |c| c == 'w' }.tally
      best   = counts.max_by { |_, v| v }&.first || 'r'
      action['wild_color'] = full_color(best)
    end
    action
  end

  def isolated_number?(card)
    fig = figure(card)
    @hand.one? { |c| figure(c) == fig }
  end

  # Heuristic chain starter (same as before).
  def heuristic_chain_starter(cards)
    best = nil
    score_best = 0.0
    cards.each do |c|
      s = heuristic_score(c)
      if s > score_best ||
         (s == score_best && number?(c) && best && !number?(best)) ||
         (s == score_best && number?(c) && best && number?(best) && figure(c).to_i > figure(best).to_i)
        best = c
        score_best = s
      end
    end
    score_best >= 2 ? best : nil
  end

  def heuristic_score(card)
    clr = color(card)
    fig = figure(card)
    rest = @hand - [card]
    score = rest.count { |c| color(c) == clr || figure(c) == fig }
    if number?(card)
      alt = rest.select { |c| figure(c) == fig && color(c) != clr }
      score += alt.size * 0.3
    end
    score -= 0.5 unless number?(card)
    score
  end
end

############################################################
# Thin I/O wrapper                                          #
############################################################
class SmarterAgent
  def run
    while (line = $stdin.gets)
      data = JSON.parse(line.strip)
      case data['type']
      when 'request_action'
        puts JSON.generate(ActionDecider.new(data['state']).decide)
        $stdout.flush
      when 'game_end'
        break
      end
    end
  end
end

SmarterAgent.new.run if $PROGRAM_NAME == __FILE__
