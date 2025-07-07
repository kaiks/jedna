#!/usr/bin/env ruby
# frozen_string_literal: true

# Analyze Results - Statistical analysis tool for tournament results
#
# Calculates Wilson score confidence intervals for win rates, providing
# statistically meaningful bounds on agent performance.
#
# Features:
# - 90%, 95%, and 99% confidence intervals
# - Current margin of error calculation
# - Recommendations for additional games needed
# - Based on Wilson score interval (better than normal approximation)
#
# Usage: ruby analyze_results.rb <wins> <total_games> [confidence]
# Example: ruby analyze_results.rb 570 1000 0.95

def wilson_confidence_interval(wins, total_games, confidence = 0.95)
  return [0, 0] if total_games.zero?

  z_scores = {
    0.90 => 1.645,
    0.95 => 1.96,
    0.99 => 2.576
  }
  z = z_scores[confidence] || 1.96

  p_hat = wins.to_f / total_games

  # Wilson score interval
  denominator = 1 + z**2 / total_games
  center = (p_hat + z**2 / (2 * total_games)) / denominator
  margin = z * Math.sqrt(p_hat * (1 - p_hat) / total_games + z**2 / (4 * total_games**2)) / denominator

  lower = [center - margin, 0].max
  upper = [center + margin, 1].min

  [lower, upper]
end

# Parse command line arguments
if ARGV.length < 2
  puts 'Usage: ruby analyze_results.rb <wins> <total_games> [confidence_level]'
  puts 'Example: ruby analyze_results.rb 570 1000 0.95'
  exit 1
end

wins = ARGV[0].to_i
total_games = ARGV[1].to_i
confidence = ARGV[2]&.to_f || 0.95

if wins > total_games
  puts 'Error: Wins cannot exceed total games'
  exit 1
end

win_rate = (wins.to_f / total_games * 100).round(1)

# Calculate intervals for different confidence levels
intervals = {
  0.90 => wilson_confidence_interval(wins, total_games, 0.90),
  0.95 => wilson_confidence_interval(wins, total_games, 0.95),
  0.99 => wilson_confidence_interval(wins, total_games, 0.99)
}

puts 'Tournament Results Analysis'
puts '=' * 50
puts "Games played: #{total_games}"
puts "Games won: #{wins}"
puts "Observed win rate: #{win_rate}%"
puts
puts 'Confidence Intervals:'
intervals.each do |conf, (lower, upper)|
  lower_pct = (lower * 100).round(1)
  upper_pct = (upper * 100).round(1)
  margin = ((upper - lower) / 2 * 100).round(1)
  puts "#{(conf * 100).to_i}% confidence: [#{lower_pct}%, #{upper_pct}%] (±#{margin}%)"
end

# Recommendation for more games
current_margin = ((intervals[confidence][1] - intervals[confidence][0]) / 2 * 100).round(1)
if current_margin > 2.0
  games_needed = ((2.576**2 * 0.5 * 0.5) / (0.02**2)).ceil
  additional_games = games_needed - total_games
  puts
  puts "Current margin: ±#{current_margin}%"
  puts "For ±2% margin at 99% confidence, play #{additional_games} more games"
end
