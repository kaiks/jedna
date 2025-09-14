#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

# Basic Jedna agent that plays the first available card
class SimpleAgent
  COLOR_NAMES = {
    'r' => 'red',
    'b' => 'blue',
    'g' => 'green',
    'y' => 'yellow'
  }.freeze

  def run
    loop do
      input = gets
      break if input.nil?

      process_message(JSON.parse(input))
    end
  end

  private

  def process_message(data)
    case data['type']
    when 'request_action'
      respond_with_action(decide_action(data['state']))
    when 'game_end'
      exit
    end
  end

  def respond_with_action(action)
    puts JSON.generate(action)
    $stdout.flush
  end

  def decide_action(state)
    if state['playable_cards']&.any?
      play_card(state['playable_cards'].first, state['hand'])
    elsif state['available_actions']&.include?('draw')
      { 'action' => 'draw' }
    else
      { 'action' => 'pass' }
    end
  end

  def play_card(card, hand)
    action = { 'action' => 'play', 'card' => card }
    action.merge!(wild_color_choice(card, hand)) if wild_card?(card)
    action
  end

  def wild_card?(card)
    card == 'w' || card.start_with?('wd')
  end

  def wild_color_choice(_card, hand)
    best_color = most_common_color(hand)
    { 'wild_color' => COLOR_NAMES.fetch(best_color, 'red') }
  end

  def most_common_color(hand)
    colors = hand.map { |c| c[0] }.reject { |c| c == 'w' }
    color_counts = colors.tally
    color_counts.max_by { |_, count| count }&.first || 'r'
  end
end

SimpleAgent.new.run if __FILE__ == $PROGRAM_NAME
