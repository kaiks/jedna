#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

class SimpleAgent
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
    # Simple strategy: play first playable card, otherwise draw
    if state['playable_cards']&.any?
      card = state['playable_cards'].first
      action = { 'action' => 'play', 'card' => card }

      # Add color for wild cards
      if card == 'w' || card.start_with?('wd')
        # Pick the color we have most of
        colors = state['hand'].map { |c| c[0] }.reject { |c| c == 'w' }
        color_counts = colors.tally
        best_color = color_counts.max_by { |_, count| count }&.first || 'r'
        action['wild_color'] = color_name(best_color)
      end

      action
    elsif state['available_actions']&.include?('draw')
      { 'action' => 'draw' }
    else
      { 'action' => 'pass' }
    end
  end

  def color_name(letter)
    { 'r' => 'red', 'b' => 'blue', 'g' => 'green', 'y' => 'yellow' }[letter]
  end
end

SimpleAgent.new.run if __FILE__ == $PROGRAM_NAME
