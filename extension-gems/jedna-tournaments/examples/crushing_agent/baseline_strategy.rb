# frozen_string_literal: true

# Baseline probability and chain strategy used by CrushingAgent.
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
# This is deliberately support code rather than another executable arena agent.
class CrushingBaselineStrategy
  PROBABILITY_THRESHOLD = 10
  MAX_PERMUTATION_SIZE = 8
  DISCOUNT_FACTOR = 0.99
  PathSearch = Data.define(:start, :cards, :final_mask, :selected_counts, :memo)

  def decide(state)
    @state = state
    @hand = state['hand'] || []
    @playable_cards = state['playable_cards'] || []
    @parsed_cards = {}

    return draw_or_pass unless @playable_cards.any?

    if use_probability_strategy?
      probability_based_action || default_play
    else
      chain_based_action || default_play
    end
  end

  private

  def use_probability_strategy?
    @hand.size >= PROBABILITY_THRESHOLD || in_war?
  end

  def in_war?
    (@state['stacked_cards'] || @state['war_cards_to_draw'] || 0).positive?
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
      wilds, non_wild = @playable_cards.partition { |c| wild_card?(c) }

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
        longest = backtrack_chain(stack, path, longest)
      else
        advance_chain(stack, path, neighbors.first)
      end
    end

    longest
  end

  def backtrack_chain(stack, path, longest)
    longest = path.dup if path.size > longest.size
    stack.pop
    path.pop
    longest
  end

  def advance_chain(stack, path, card)
    stack.push(card)
    path.push(card)
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
    final_mask = (1 << cards.length) - 1
    search = PathSearch.new(
      start,
      cards,
      final_mask,
      (0..final_mask).map { |mask| mask.digits(2).sum },
      {}
    )
    _score, path = best_probability_suffix(search, nil, 0)
    path
  end

  def best_probability_suffix(search, last_index, selected_mask)
    return [0.0, []] if selected_mask == search.final_mask

    key = [last_index, selected_mask]
    return search.memo.fetch(key) if search.memo.key?(key)

    current_card = last_index.nil? ? search.start : search.cards[last_index]
    best_score = -Float::INFINITY
    best_path = []

    search.cards.each_index do |index|
      next if selected_mask[index] == 1

      score, path = probability_candidate(search, current_card, selected_mask, index)
      next unless score > best_score

      best_score = score
      best_path = path
    end

    search.memo[key] = [best_score, best_path]
  end

  def probability_candidate(search, current_card, selected_mask, index)
    next_score, next_path = best_probability_suffix(search, index, selected_mask | (1 << index))
    position = search.selected_counts[selected_mask]
    discount = DISCOUNT_FACTOR**(search.cards.length - position - 1)
    score = (transition_probability(current_card, search.cards[index], position) * discount) + next_score
    [score, [search.cards[index]] + next_path]
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

  def transition_probability(from_card, to_card, position)
    from = parse_card(from_card)
    to = parse_card(to_card)
    special = special_transition(from_card, to_card, from, to, position)
    return special if special

    from_color, from_figure = from
    to_color, to_figure = to
    return 0.85 if from_color == to_color && from_figure == to_figure
    return 0.6 if from_color == to_color
    return 0.2 if from_figure == to_figure

    0.05
  end

  def special_transition(from_card, to_card, from, to, position)
    from_color, from_figure = from
    to_color, to_figure = to
    return 1.0 if from_figure == 's' && (to_color == from_color || to_figure == 's')
    return 1.0 if to_card == 'wd4'
    return 0.95 if to_card == 'w'

    0.85 if wild_card?(from_card) && position != 0
  end

  def playable_on?(card, top_card)
    return true if wild_card?(card)

    card_color, card_figure = parse_card(card)
    top_color, top_figure = parse_card(top_card)

    card_color == top_color || card_figure == top_figure
  end

  def parse_card(card)
    @parsed_cards ||= {}
    return @parsed_cards.fetch(card) if @parsed_cards.key?(card)

    @parsed_cards[card] = parse_uncached_card(card)
  end

  def parse_uncached_card(card)
    return %w[w wild] if %w[w wd4].include?(card)

    [card[0], card[1..]]
  end

  def wild_card?(card)
    %w[w wd4].include?(card)
  end

  def play_card(card, hand)
    action = { 'action' => 'play', 'card' => card }
    return action unless wild_card?(card)

    colors = hand.map { |c| c[0] }.reject { |c| c == 'w' }
    best_color = colors.tally.max_by { |_, count| count }&.first || 'r'
    action['wild_color'] = color_name(best_color)
    action
  end

  def color_name(letter)
    {
      'r' => 'red',
      'b' => 'blue',
      'g' => 'green',
      'y' => 'yellow'
    }.fetch(letter, 'red')
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
