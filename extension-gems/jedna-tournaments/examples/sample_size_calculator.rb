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

require_relative 'lib/tournament_statistics'

# Displays sample size requirements for various scenarios
class SampleSizeDisplay
  include TournamentStatistics

  SCENARIOS = [
    { confidence: 0.90, margin: 0.05, name: '90% confidence, ±5%' },
    { confidence: 0.95, margin: 0.05, name: '95% confidence, ±5%' },
    { confidence: 0.95, margin: 0.02, name: '95% confidence, ±2%' },
    { confidence: 0.99, margin: 0.02, name: '99% confidence, ±2%' },
    { confidence: 0.99, margin: 0.01, name: '99% confidence, ±1%' }
  ].freeze

  EXAMPLE_GAME_COUNTS = [100, 200, 500, 1000, 2000, 4145].freeze
  EXAMPLE_WIN_RATE = 0.57

  def display
    display_header
    display_scenarios
    display_recommendation
    display_examples
    display_notes
  end

  private

  def display_header
    puts 'Sample Size Calculator for Tournament Win Rate Estimation'
    puts '=' * 60
    puts
  end

  def display_scenarios
    puts 'Required number of games for different confidence levels:'
    puts

    SCENARIOS.each do |scenario|
      games = SampleSizeCalculator.calculate(
        confidence: scenario[:confidence],
        margin: scenario[:margin]
      )
      puts "#{scenario[:name]}: #{games} games"
    end
  end

  def display_recommendation
    puts
    puts '=' * 60
    puts 'For 99% confidence within ±2% margin of error:'
    puts "You need to play #{SampleSizeCalculator.calculate} games"
    puts
  end

  def display_examples
    puts "Confidence intervals for a #{(EXAMPLE_WIN_RATE * 100).to_i}% observed win rate:"
    puts

    EXAMPLE_GAME_COUNTS.each do |games|
      wins = (games * EXAMPLE_WIN_RATE).round
      interval = ConfidenceInterval.new(wins, games)
      lower, upper = interval.calculate
      margin = interval.margin_of_error

      puts format('After %4d games: [%.1f%%, %.1f%%] (±%.1f%%)',
                  games,
                  lower * 100,
                  upper * 100,
                  margin)
    end
  end

  def display_notes
    puts
    puts 'Note: These calculations assume:'
    puts '- Independent game outcomes'
    puts '- Consistent agent performance'
    puts '- No learning/adaptation during tournament'
  end
end

# Main execution
SampleSizeDisplay.new.display if __FILE__ == $PROGRAM_NAME
