#!/usr/bin/env ruby
# frozen_string_literal: true

# Smart Agent - Probability and chain-based Jedna player
#
# Implements two strategies:
# - Probability-based: Calculates transition probabilities between cards
# - Chain-based: Finds longest playable sequence of cards
#
# Strategy selection:
# - Uses probability approach when hand size >= 10 or in war
# - Uses chain approach for smaller hands
#
# Performance optimizations:
# - Limits permutations for large hands
# - Uses greedy algorithm for very large hands
#
# Usage: ./smart_agent.rb (communicates via JSON on stdin/stdout)

require_relative 'lib/base_agent'

# Probability and chain-based strategy agent
class SmartAgent < BaseAgent
  PROBABILITY_THRESHOLD = 10
  MAX_PERMUTATION_SIZE = 8
  DISCOUNT_FACTOR = 0.99

  private

  def decide_action(state)
    @state = state
    @hand = state['hand'] || []
    @playable_cards = state['playable_cards'] || []

    return draw_or_pass unless @playable_cards.any?

    if use_probability_strategy?
      probability_based_action || default_play
    else
      chain_based_action || default_play
    end
  end

  def use_probability_strategy?
    @hand.size >= PROBABILITY_THRESHOLD || in_war?
  end

  def in_war?
    (@state['war_cards_to_draw'] || 0).positive?
  end

  def probability_based_action
    input_cards = prepare_probability_input
    best_path = find_highest_probability_path(input_cards)

    return nil unless best_path.any? && @playable_cards.include?(best_path.first)

    play_card(best_path.first, @hand)
  end

  def prepare_probability_input
    target = @state['top_card']
    input = [target]

    if @hand.size >= PROBABILITY_THRESHOLD
      # Strategic subset for performance
      non_wild = @playable_cards.reject { |c| wild_card?(c) }
      wilds = @playable_cards.select { |c| wild_card?(c) }

      input + non_wild.take(9 - wilds.size) + wilds
    else
      input + @hand
    end
  end

  def chain_based_action
    longest_chain = find_longest_chain
    return nil unless longest_chain.any?

    play_card(longest_chain.first, @hand)
  end

  def find_longest_chain
    max_length = 0
    best_chain = []

    @playable_cards.each do |start_card|
      chain = explore_chain_from(start_card)
      if chain.size > max_length
        max_length = chain.size
        best_chain = chain
      end
    end

    best_chain
  end

  def explore_chain_from(start_card)
    visited = @hand.to_h { |card| [card, false] }
    path = [start_card]
    stack = [start_card]
    longest = [start_card]

    while stack.any?
      current = stack.last
      visited[current] = true if visited.key?(current)

      neighbors = find_unvisited_neighbors(current, visited)

      if neighbors.empty?
        longest = path.dup if path.size > longest.size
        stack.pop
        path.pop
      else
        next_card = neighbors.first
        stack.push(next_card)
        path.push(next_card)
      end
    end

    longest
  end

  def find_unvisited_neighbors(card, visited)
    @hand.select do |neighbor|
      !visited[neighbor] && playable_on?(neighbor, card)
    end
  end

  def find_highest_probability_path(cards)
    return [] if cards.size < 2

    start = cards.first
    remaining = cards[1..]

    if remaining.size > MAX_PERMUTATION_SIZE
      greedy_path(start, remaining)
    else
      best_permutation_path(start, remaining)
    end
  end

  def best_permutation_path(start, cards)
    best_prob = 0
    best_path = []

    cards.permutation.each do |perm|
      prob = calculate_path_probability([start] + perm)
      if prob > best_prob
        best_prob = prob
        best_path = perm
      end
    end

    best_path
  end

  def greedy_path(start, cards)
    path = []
    current = start
    remaining = cards.dup

    while remaining.any?
      next_card = find_best_next_card(current, remaining, path.size)
      break unless next_card

      path << next_card
      current = next_card
      remaining.delete(next_card)
    end

    path
  end

  def find_best_next_card(current, candidates, position)
    candidates.max_by do |card|
      transition_probability(current, card, position)
    end
  end

  def calculate_path_probability(path)
    return 0 if path.size < 2

    probabilities = (0...(path.size - 1)).map do |i|
      transition_probability(path[i], path[i + 1], i)
    end

    1 + apply_discounting(probabilities).sum
  end

  def apply_discounting(probabilities)
    factor = 1.0
    probabilities.reverse.map do |prob|
      discounted = prob * factor
      factor *= DISCOUNT_FACTOR
      discounted
    end.reverse
  end

  def transition_probability(from_card, to_card, position)
    from_color, from_figure = parse_card(from_card)
    to_color, to_figure = parse_card(to_card)

    # Skip chain bonus
    return 1.0 if from_figure == 's' && (to_color == from_color || to_figure == 's')

    # Wild cards
    return 1.0 if to_card == 'wd4'
    return 0.95 if to_card == 'w'
    return 0.85 if wild_card?(from_card) && position != 0

    # Same card type
    return 0.85 if from_color == to_color && from_figure == to_figure

    # Color or figure match
    return 0.6 if from_color == to_color
    return 0.2 if from_figure == to_figure

    0.05
  end

  def playable_on?(card, top_card)
    return true if wild_card?(card)

    card_color, card_figure = parse_card(card)
    top_color, top_figure = parse_card(top_card)

    card_color == top_color || card_figure == top_figure
  end

  def parse_card(card)
    return %w[w wild] if %w[w wd4].include?(card)

    [card[0], card[1..]]
  end

  def default_play
    play_card(@playable_cards.first, @hand)
  end

  def draw_or_pass
    if @state['available_actions']&.include?('draw')
      { 'action' => 'draw' }
    else
      { 'action' => 'pass' }
    end
  end
end

SmartAgent.new.run if __FILE__ == $PROGRAM_NAME
