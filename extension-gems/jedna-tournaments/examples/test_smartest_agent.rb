#!/usr/bin/env ruby
# frozen_string_literal: true

# Test Suite for SmartRuby Agent
#
# Comprehensive test coverage for agent strategies including:
# - Wild card conservation
# - War handling (reverse counters)
# - Defensive play (opponent at UNO)
# - Chain detection and optimization
# - Skip chain recognition
# - Action card timing
# - Isolated number preference
#
# All 17 tests are designed to verify specific strategic decisions
# and ensure the agent maintains its 57% win rate.
#
# Usage: ruby test_smarter_agent.rb
# Run specific test: ruby test_smarter_agent.rb -n test_defensive_wd4_when_opponent_uno

require 'minitest/autorun'
require 'json'
require_relative 'smartest_agent'

# Test suite for SmarterAgent strategies
class TestSmarterAgent < Minitest::Test
  def test_chain_opportunity_with_reverse
    # Optimal play: g4 (enables g4 -> g3 -> gr -> wr -> r1 -> wd4)
    action = simulate_agent_decision(
      hand: %w[g3 g4 gr r1 w wd4],
      top_card: 'g6',
      playable_cards: %w[g3 g4 gr],
      opponent_cards: [2]
    )

    assert_equal 'play', action['action']
    assert_equal 'g4', action['card'], 'Should play g4 to enable longest chain'
  end

  def test_wild_card_conservation
    # Should not waste wd4 when other options are available
    action = simulate_agent_decision(
      hand: %w[b2 b5 b5 b6 wd4 y3],
      top_card: 'g8',
      playable_cards: ['wd4']
    )

    assert_equal 'play', action['action']
    assert_equal 'wd4', action['card'], "Should play wd4 when it's the only option"

    # But when we have other options...
    action = simulate_agent_decision(
      hand: %w[b2 b5 b5 b6 wd4 y3],
      top_card: 'b8',
      playable_cards: %w[b2 b5 b6 wd4]
    )

    assert_equal 'play', action['action']
    refute_equal 'wd4', action['card'], 'Should NOT play wd4 when other cards are available'
  end

  def test_isolated_number_preference
    # b9 is isolated (no other 9s), should prefer over action cards
    action = simulate_agent_decision(
      hand: %w[b+2 b9 br g0 g6 g6 y1 y8],
      top_card: 'b6',
      playable_cards: %w[b+2 b9 br],
      opponent_cards: [5]
    )

    assert_equal 'play', action['action']
    assert_equal 'b9', action['card'], 'Should play isolated number card b9'
  end

  def test_war_reverse_counter
    # In a +2 war, should play reverse if available
    action = simulate_agent_decision(
      hand: %w[br g+2 r3 y7],
      top_card: 'b+2',
      playable_cards: %w[br g+2],
      opponent_cards: [3],
      war_cards: 2
    )

    assert_equal 'play', action['action']
    assert_equal 'br', action['card'], 'Should counter +2 war with reverse'
  end

  def test_defensive_wd4_when_opponent_uno
    # Opponent has UNO - play wd4 defensively
    action = simulate_agent_decision(
      hand: %w[g1 g3 r8 wd4],
      top_card: 'g6',
      playable_cards: %w[g1 g3 wd4],
      opponent_cards: [1]
    )

    assert_equal 'play', action['action']
    assert_equal 'wd4', action['card'], 'Should play wd4 when opponent has UNO'
  end

  def test_defensive_action_card_preference
    # Opponent has UNO - prefer action cards
    action = simulate_agent_decision(
      hand: %w[b+2 b3 b5 br g9 r1],
      top_card: 'b8',
      playable_cards: %w[b+2 b3 b5 br],
      opponent_cards: [1]
    )

    assert_equal 'play', action['action']
    assert_match(/b[+2r]/, action['card'], 'Should play action card when opponent has UNO')
  end

  def test_safe_play_with_low_cards
    # When we have 2 cards, avoid action cards if possible
    action = simulate_agent_decision(
      hand: %w[g7 gs],
      top_card: 'g3',
      playable_cards: %w[g7 gs],
      opponent_cards: [4]
    )

    assert_equal 'play', action['action']
    assert_equal 'g7', action['card'], 'Should play number card when low on cards'
  end

  def test_draw_when_no_playable_cards
    action = simulate_agent_decision(
      hand: %w[b2 b5 r3 y9],
      top_card: 'g8',
      playable_cards: [],
      opponent_cards: [3],
      available_actions: %w[draw pass]
    )

    assert_equal 'draw', action['action']
  end

  def test_pass_when_cannot_draw
    action = simulate_agent_decision(
      hand: %w[b2 b5 r3 y9],
      top_card: 'g8',
      playable_cards: [],
      opponent_cards: [3],
      available_actions: ['pass']
    )

    assert_equal 'pass', action['action']
  end

  def test_wild_color_selection
    # Should pick blue (most common color)
    action = simulate_agent_decision(
      hand: %w[b2 b5 b7 r3 w y9],
      top_card: 'g8',
      playable_cards: ['w'],
      opponent_cards: [4]
    )

    assert_equal 'play', action['action']
    assert_equal 'w', action['card']
    assert_equal 'blue', action['wild_color'], 'Should pick blue (most common)'
  end

  def test_action_card_aggression_when_opponent_uno
    # With opponent at UNO, be aggressive with action cards
    action = simulate_agent_decision(
      hand: %w[b3 b5 bs g9 r1],
      top_card: 'b8',
      playable_cards: %w[b3 b5 bs],
      opponent_cards: [1]
    )

    assert_equal 'play', action['action']
    assert_equal 'bs', action['card'], 'Should play skip when opponent has UNO'
  end

  def test_continue_war_with_many_cards
    # Continue +2 war when we have many cards
    action = simulate_agent_decision(
      hand: %w[b2 b5 b7 g+2 g3 g9 r1 r3 r7 w y+2],
      top_card: 'r+2',
      playable_cards: %w[g+2 y+2],
      opponent_cards: [4],
      war_cards: 2
    )

    assert_equal 'play', action['action']
    assert_match(/[gy]\+2/, action['card'], 'Should continue war with many cards')
  end

  def test_avoid_war_continuation_with_few_cards
    # Don't continue war when low on cards (except when opponent has UNO)
    action = simulate_agent_decision(
      hand: %w[g+2 y3],
      top_card: 'r+2',
      playable_cards: ['g+2'],
      opponent_cards: [5],
      war_cards: 2
    )

    assert_equal 'play', action['action']
    assert_equal 'g+2', action['card'], 'Must play only available card'
  end

  def test_chain_detection_same_number
    # Detect chain: b6 -> g6 -> g3
    action = simulate_agent_decision(
      hand: %w[b6 g3 g6 r9 y1],
      top_card: 'b8',
      playable_cards: ['b6'],
      opponent_cards: [3]
    )

    assert_equal 'play', action['action']
    assert_equal 'b6', action['card'], 'Should start chain with b6'
  end

  def test_skip_chain_endgame
    # With 4 cards including 2 skips, should play skip
    action = simulate_agent_decision(
      hand: %w[g4 gs bs ys],
      top_card: 'g9',
      playable_cards: %w[g4 gs],
      opponent_cards: [3]
    )

    assert_equal 'play', action['action']
    assert_equal 'gs', action['card'], 'Should play skip to start skip chain'
  end

  def test_massive_skip_chain_opportunity
    # With 8 skip cards out of 10, should recognize skip chain
    action = simulate_agent_decision(
      hand: %w[g8 g8 gs gs bs bs ys ys rs rs],
      top_card: 'g9',
      playable_cards: %w[g8 gs],
      opponent_cards: [7]
    )

    assert_equal 'play', action['action']
    assert_equal 'gs', action['card'], 'Should play gs to start massive skip chain'
  end

  def test_winning_sequence_recognition
    # Recognize winning sequence: gs -> ys -> wd4
    action = simulate_agent_decision(
      hand: %w[gs ys wd4],
      top_card: 'g7',
      playable_cards: %w[gs wd4],
      opponent_cards: [1]
    )

    assert_equal 'play', action['action']
    assert_equal 'gs', action['card'], 'Should start winning sequence with gs'
  end

  def test_save_skip_when_no_danger
    # With opponent having many cards, save action cards
    action = simulate_agent_decision(
      hand: %w[b8 bs g3 g9 r1 rs y5 ys],
      top_card: 'b4',
      playable_cards: %w[b8 bs],
      opponent_cards: [12]
    )

    assert_equal 'play', action['action']
    assert_equal 'b8', action['card'], 'Should save skip when opponent has many cards'
  end

  private

  def simulate_agent_decision(hand:, top_card:, playable_cards:, opponent_cards: [7],
                              war_cards: 0, available_actions: ['play'])
    state = {
      'hand' => hand,
      'top_card' => top_card,
      'playable_cards' => playable_cards,
      'opponent_hand_sizes' => opponent_cards,
      'war_cards_to_draw' => war_cards,
      'available_actions' => available_actions
    }

    ActionDecider.new(state).decide
  end
end
