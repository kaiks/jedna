#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

class SmartAgent
  def initialize
    @debug = false
  end

  def run
    loop do
      input = gets
      break if input.nil?

      data = JSON.parse(input)

      case data['type']
      when 'request_action'
        action = decide_action(data['state'])
        puts JSON.generate(action)
        $stdout.flush
      when 'game_end'
        break
      end
    end
  end

  private

  def decide_action(state)
    legal_actions = state['available_actions'] || []
    state['hand'] || []
    state['top_card']
    playable_cards = state['playable_cards'] || []

    # Get legal actions except draw and pass
    legal_actions_except_draw_pass = playable_cards

    if legal_actions_except_draw_pass.any?
      # Choose strategy based on game state
      action = if should_use_probability_strategy?(state)
                 probability_based_action(state, legal_actions_except_draw_pass)
               else
                 longest_chain_action(state, legal_actions_except_draw_pass)
               end

      return action if action
    end

    # Default actions
    if legal_actions.include?('draw')
      { 'action' => 'draw' }
    elsif legal_actions.include?('pass')
      { 'action' => 'pass' }
    else
      { 'action' => 'pass' }
    end
  end

  def should_use_probability_strategy?(state)
    # Use probability strategy when hand is large or in wars
    hand_size = state['hand']&.size || 0
    in_war = state['war_cards_to_draw']&.positive?

    hand_size >= 10 || in_war
  end

  def probability_based_action(state, legal_actions)
    hand = state['hand'] || []
    target = state['top_card']

    # Prepare input cards (target + subset of hand for performance)
    input_cards = [target]

    # Limit cards for performance
    if hand.size >= 10
      # Take strategic subset of cards
      corrected_legal = legal_actions.reject { |c| %w[w wd4].include?(c) }

      # Add one of each wild type if available
      wild = legal_actions.find { |c| c == 'w' }
      wild_draw_4 = legal_actions.find { |c| c == 'wd4' }

      corrected_legal << wild if wild
      corrected_legal << wild_draw_4 if wild_draw_4

      input_cards += corrected_legal.take(9)
    else
      input_cards += hand
    end

    # Find best path using probability calculations
    best_path = find_highest_probability_path(input_cards)

    if @debug
      puts "Target: #{target}"
      puts "Input cards: #{input_cards}"
      puts "Best path: #{best_path}"
    end

    # Play first card in best path if it's legal
    return unless best_path.any? && legal_actions.include?(best_path.first)

    card = best_path.first
    build_play_action(card, best_path[1])
  end

  def longest_chain_action(state, legal_actions)
    hand = state['hand'] || []
    target = state['top_card']

    # Find longest chain starting from each legal action
    longest_chain = find_longest_chain(hand, legal_actions, target)

    return unless longest_chain.any?

    card = longest_chain.first
    build_play_action(card, longest_chain[1])
  end

  def find_longest_chain(hand, starting_actions, _top_card)
    max_length = 0
    longest_path = []

    starting_actions.each do |start_card|
      visited = hand.to_h { |card| [card, false] }
      path = [start_card]
      stack = [start_card]

      while stack.any?
        curr_card = stack.last
        visited[curr_card] = true if visited.key?(curr_card)

        # Find unvisited playable neighbors
        neighbors = hand.select do |card|
          !visited[card] && is_playable?(card, curr_card)
        end

        if neighbors.empty?
          # End of path - check if it's the longest
          if path.size > max_length
            max_length = path.size
            longest_path = path.dup
          end
          stack.pop
          path.pop
        else
          # Continue exploring
          next_card = neighbors.first
          stack.push(next_card)
          path.push(next_card)
        end
      end
    end

    longest_path
  end

  def find_highest_probability_path(cards)
    return [] if cards.empty?

    start_card = cards.first
    remaining_cards = cards[1..]

    return [] if remaining_cards.empty?

    # For performance, limit permutations for large sets
    if remaining_cards.size > 8
      # Use greedy approach for large hands
      return greedy_path(start_card, remaining_cards)
    end

    highest_prob = 0
    best_path = []

    # Try all permutations to find best path
    remaining_cards.permutation.each do |perm|
      candidate_path = [start_card] + perm
      current_prob = calculate_path_probability(candidate_path)

      if current_prob > highest_prob
        highest_prob = current_prob
        best_path = perm
      end
    end

    best_path
  end

  def greedy_path(start_card, cards)
    path = []
    current = start_card
    remaining = cards.dup

    while remaining.any?
      # Find best next card based on transition probability
      best_card = nil
      best_prob = 0

      remaining.each do |card|
        prob = transition_probability(current, card, path.size)
        if prob > best_prob
          best_prob = prob
          best_card = card
        end
      end

      break unless best_card

      path << best_card
      current = best_card
      remaining.delete(best_card)
    end

    path
  end

  def calculate_path_probability(path)
    return 0 if path.size < 2

    probs = []
    (0...path.size - 1).each do |i|
      probs << transition_probability(path[i], path[i + 1], i)
    end

    # Apply discounting
    discounted_probs = discount_probability(probs)

    # Sum probabilities
    1 + discounted_probs.sum
  end

  def discount_probability(prob_list)
    discounted_probs = []
    discount_factor = 1.0

    prob_list.reverse.each do |prob|
      discounted_prob = prob * discount_factor
      discounted_probs.unshift(discounted_prob)
      discount_factor *= 0.99
    end

    discounted_probs
  end

  def transition_probability(card_from, card_to, position)
    from_color = color(card_from)
    from_figure = figure(card_from)
    to_color = color(card_to)
    to_figure = figure(card_to)

    # Special rules for skip cards
    return 1.00 if from_figure == 'skip' && (to_color == from_color || to_figure == 'skip')

    # Wild cards have high probability
    case to_figure
    when 'wild+4', 'wd4'
      return 1.00
    when 'wild', 'w'
      return 0.95
    end

    # Wild cards to other cards (not first position)
    return 0.85 if ['wild', 'wild+4', 'w', 'wd4'].include?(from_figure) && position != 0

    # Same card (color and figure)
    return 0.85 if from_color == to_color && from_figure == to_figure

    # Same color
    return 0.60 if from_color == to_color

    # Same figure
    return 0.20 if from_figure == to_figure

    # Default low probability
    0.05
  end

  def is_playable?(card, top_card)
    # Wild cards are always playable
    return true if ['wild', 'wild+4'].include?(figure(card)) ||
                   card == 'w' || card == 'wd4'

    # Same color or same figure
    color(card) == color(top_card) || figure(card) == figure(top_card)
  end

  def build_play_action(card, next_card = nil)
    action = { 'action' => 'play', 'card' => card }

    # Add wild color if needed
    if %w[w wd4].include?(card)
      wild_color = if next_card
                     # Use color of next card in chain
                     color_name(color(next_card))
                   else
                     # Default to most common color in hand
                     'red'
                   end
      action['wild_color'] = wild_color
    end

    action
  end

  def color(card)
    return 'r' if card.nil? || card.empty?

    # Handle special notation
    case card
    when 'w', 'wd4'
      'w'
    else
      card[0]
    end
  end

  def figure(card)
    return '' if card.nil? || card.empty?

    # Handle special notation
    case card
    when 'w'
      'wild'
    when 'wd4'
      'wild+4'
    else
      # Extract figure from card string (e.g., "r5" -> "5", "bs" -> "skip")
      fig = card[1..]

      # Map single letter figures to full names
      case fig
      when 's'
        'skip'
      when 'r'
        'reverse'
      when 'd2'
        'draw2'
      else
        fig
      end
    end
  end

  def color_name(letter)
    {
      'r' => 'red',
      'b' => 'blue',
      'g' => 'green',
      'y' => 'yellow',
      'w' => 'red' # default for wild
    }[letter] || 'red'
  end
end

# Run agent if called directly
SmartAgent.new.run if __FILE__ == $PROGRAM_NAME
