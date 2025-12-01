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

require_relative 'lib/tournament_statistics'

# Command-line interface for tournament result analysis
class ResultAnalyzer
  include TournamentStatistics

  def initialize(wins:, total_games:, confidence: 0.95)
    @wins = wins
    @total_games = total_games
    @confidence = confidence
  end

  def analyze
    validate_inputs!
    display_results
    display_confidence_intervals
    display_recommendations if needs_more_games?
  end

  private

  attr_reader :wins, :total_games, :confidence

  def validate_inputs!
    raise ArgumentError, 'Wins cannot exceed total games' if wins > total_games
  end

  def win_rate
    @win_rate ||= (wins.to_f / total_games * 100).round(1)
  end

  def confidence_intervals
    @confidence_intervals ||= {
      0.90 => ConfidenceInterval.new(wins, total_games, 0.90).calculate,
      0.95 => ConfidenceInterval.new(wins, total_games, 0.95).calculate,
      0.99 => ConfidenceInterval.new(wins, total_games, 0.99).calculate
    }
  end

  def current_margin
    @current_margin ||= ConfidenceInterval.new(wins, total_games, confidence).margin_of_error
  end

  def needs_more_games?
    current_margin > 2.0
  end

  def display_results
    puts 'Tournament Results Analysis'
    puts '=' * 50
    puts "Games played: #{total_games}"
    puts "Games won: #{wins}"
    puts "Observed win rate: #{win_rate}%"
  end

  def display_confidence_intervals
    puts "\nConfidence Intervals:"
    confidence_intervals.each do |conf, (lower, upper)|
      lower_pct = (lower * 100).round(1)
      upper_pct = (upper * 100).round(1)
      margin = ((upper - lower) / 2 * 100).round(1)
      puts "#{(conf * 100).to_i}% confidence: [#{lower_pct}%, #{upper_pct}%] (±#{margin}%)"
    end
  end

  def display_recommendations
    games_needed = SampleSizeCalculator.calculate
    additional_games = games_needed - total_games

    puts "\nCurrent margin: ±#{current_margin}%"
    puts "For ±2% margin at 99% confidence, play #{additional_games} more games"
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  if ARGV.length < 2
    puts 'Usage: ruby analyze_results.rb <wins> <total_games> [confidence_level]'
    puts 'Example: ruby analyze_results.rb 570 1000 0.95'
    exit 1
  end

  analyzer = ResultAnalyzer.new(
    wins: ARGV[0].to_i,
    total_games: ARGV[1].to_i,
    confidence: ARGV[2]&.to_f || 0.95
  )

  analyzer.analyze
end
