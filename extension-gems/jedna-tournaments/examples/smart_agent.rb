#!/usr/bin/env ruby
require 'json'

class SmartAgent
  def initialize
    @cards_played = []
    @player_stats = {}
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
        STDOUT.flush
      when 'notification'
        process_notification(data['message'])
      when 'game_end'
        break
      end
    end
  end
  
  private
  
  def decide_action(state)
    @current_state = state
    
    # Update player stats
    state['other_players'].each do |player|
      @player_stats[player['id']] ||= { min_cards: 999 }
      @player_stats[player['id']][:min_cards] = [
        @player_stats[player['id']][:min_cards],
        player['cards']
      ].min
    end
    
    # Strategy depends on game state
    if state['game_state'] == 'war_+2' || state['game_state'] == 'war_wd4'
      handle_war_state(state)
    elsif someone_about_to_win?
      aggressive_play(state)
    else
      balanced_play(state)
    end
  end
  
  def handle_war_state(state)
    # In war, try to continue it if we can
    war_cards = state['game_state'] == 'war_+2' ? 
      state['playable_cards'].select { |c| c.end_with?('+2') } :
      state['playable_cards'].select { |c| c == 'wd4' }
    
    if war_cards.any?
      card = war_cards.first
      action = { 'action' => 'play', 'card' => card }
      action['wild_color'] = choose_best_color(state) if card == 'wd4'
      action
    elsif state['available_actions'].include?('pass')
      { 'action' => 'pass' }
    else
      { 'action' => 'draw' }
    end
  end
  
  def someone_about_to_win?
    @player_stats.any? { |_, stats| stats[:min_cards] <= 2 }
  end
  
  def aggressive_play(state)
    # Play offensive cards first when someone is close to winning
    offensive_cards = state['playable_cards'].select do |card|
      card.end_with?('+2') || card == 'wd4' || 
      card.end_with?('s') || card.end_with?('r')
    end
    
    if offensive_cards.any?
      card = offensive_cards.first
      action = { 'action' => 'play', 'card' => card }
      action['wild_color'] = choose_worst_color_for_next(state) if card.start_with?('wd')
      action
    elsif state['playable_cards'].any?
      play_regular_card(state)
    elsif state['available_actions'].include?('draw')
      { 'action' => 'draw' }
    else
      { 'action' => 'pass' }
    end
  end
  
  def balanced_play(state)
    # Normal play - save offensive cards for later
    regular_cards = state['playable_cards'].reject do |card|
      card.end_with?('+2') || card == 'wd4'
    end
    
    if regular_cards.any?
      card = choose_best_regular_card(regular_cards, state)
      { 'action' => 'play', 'card' => card }
    elsif state['playable_cards'].any?
      play_regular_card(state)
    elsif state['available_actions'].include?('draw')
      { 'action' => 'draw' }
    else
      { 'action' => 'pass' }
    end
  end
  
  def play_regular_card(state)
    card = state['playable_cards'].first
    action = { 'action' => 'play', 'card' => card }
    action['wild_color'] = choose_best_color(state) if card.start_with?('wd')
    action
  end
  
  def choose_best_regular_card(cards, state)
    # Prefer cards that match our most common color
    color_counts = state['hand'].map { |c| c[0] }.reject { |c| c == 'w' }.tally
    best_color = color_counts.max_by { |_, count| count }&.first
    
    cards_by_color = cards.select { |c| c.start_with?(best_color) }
    cards_by_color.any? ? cards_by_color.first : cards.first
  end
  
  def choose_best_color(state)
    colors = state['hand'].map { |c| c[0] }.reject { |c| c == 'w' }
    color_counts = colors.tally
    best_color = color_counts.max_by { |_, count| count }&.first || 'r'
    color_name(best_color)
  end
  
  def choose_worst_color_for_next(state)
    # Try to pick a color the next player might not have
    # This is a guess based on cards we've seen
    %w[red blue green yellow].sample
  end
  
  def color_name(letter)
    { 'r' => 'red', 'b' => 'blue', 'g' => 'green', 'y' => 'yellow' }[letter]
  end
  
  def process_notification(message)
    # Track cards played for better decision making
    if message =~ /played (\w+)/
      @cards_played << $1
    end
  end
end

SmartAgent.new.run if __FILE__ == $0