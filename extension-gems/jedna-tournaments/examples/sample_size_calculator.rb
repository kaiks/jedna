#!/usr/bin/env ruby
# frozen_string_literal: true

# Sample Size Calculator - Determine games needed for statistical confidence
#
# Calculates the number of games required to achieve a desired confidence
# level and margin of error in tournament results. Uses the conservative
# p=0.5 estimate for maximum variance.
#
# Key insights:
# - 100 games: ±10% margin
# - 1000 games: ±3.2% margin  
# - 4148 games: ±2% margin at 99% confidence
#
# Usage: ruby sample_size_calculator.rb
# Output: Table of required games for various confidence/margin combinations

def calculate_sample_size(confidence_level = 0.99, margin_of_error = 0.02, estimated_win_rate = 0.5)
  # Z-score for confidence level
  # 99% confidence = 2.576
  # 95% confidence = 1.96
  # 90% confidence = 1.645
  z_scores = {
    0.90 => 1.645,
    0.95 => 1.96,
    0.99 => 2.576
  }
  
  z = z_scores[confidence_level] || 2.576
  
  # Conservative estimate using p = 0.5 (maximum variance)
  # This gives us the largest required sample size
  p = estimated_win_rate
  
  # Formula: n = (z^2 * p * (1-p)) / (margin_of_error^2)
  n = (z**2 * p * (1 - p)) / (margin_of_error**2)
  
  n.ceil
end

# Wilson score interval calculation
def wilson_confidence_interval(wins, total_games, confidence = 0.99)
  return [0, 0] if total_games == 0
  
  z_scores = {
    0.90 => 1.645,
    0.95 => 1.96,
    0.99 => 2.576
  }
  z = z_scores[confidence] || 2.576
  
  p_hat = wins.to_f / total_games
  
  # Wilson score interval formula
  denominator = 1 + z**2 / total_games
  center = (p_hat + z**2 / (2 * total_games)) / denominator
  margin = z * Math.sqrt(p_hat * (1 - p_hat) / total_games + z**2 / (4 * total_games**2)) / denominator
  
  lower = [center - margin, 0].max
  upper = [center + margin, 1].min
  
  [lower, upper]
end

# Display results
puts "Sample Size Calculator for Tournament Win Rate Estimation"
puts "=" * 60
puts

# Calculate for different scenarios
scenarios = [
  { confidence: 0.90, margin: 0.05, name: "90% confidence, ±5%" },
  { confidence: 0.95, margin: 0.05, name: "95% confidence, ±5%" },
  { confidence: 0.95, margin: 0.02, name: "95% confidence, ±2%" },
  { confidence: 0.99, margin: 0.02, name: "99% confidence, ±2%" },
  { confidence: 0.99, margin: 0.01, name: "99% confidence, ±1%" }
]

puts "Required number of games for different confidence levels:"
puts
scenarios.each do |scenario|
  n = calculate_sample_size(scenario[:confidence], scenario[:margin])
  puts "#{scenario[:name]}: #{n} games"
end

puts
puts "=" * 60
puts "For 99% confidence within ±2% margin of error:"
puts "You need to play #{calculate_sample_size(0.99, 0.02)} games"
puts

# Example: Show confidence intervals for different game counts
puts "Confidence intervals for a 57% observed win rate:"
puts
game_counts = [100, 200, 500, 1000, 2000, 4145]
game_counts.each do |games|
  wins = (games * 0.57).round
  lower, upper = wilson_confidence_interval(wins, games)
  margin = ((upper - lower) / 2 * 100).round(1)
  puts "After #{games.to_s.rjust(4)} games: [#{(lower * 100).round(1)}%, #{(upper * 100).round(1)}%] (±#{margin}%)"
end

puts
puts "Note: These calculations assume:"
puts "- Independent game outcomes"
puts "- Consistent agent performance"
puts "- No learning/adaptation during tournament"