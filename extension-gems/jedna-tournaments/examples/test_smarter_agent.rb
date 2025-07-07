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
require_relative 'smarter_agent'

class TestSmarterAgent < Minitest::Test
  def setup
    @agent = SmarterAgent.new
  end

  # Test case format:
  # - hand: array of cards in hand
  # - top_card: current top card
  # - playable_cards: cards that can be played
  # - opponent_cards: array of opponent card counts
  # - expected: expected card to play
  def test_chain_opportunity_with_reverse
    # Case: g3,g4,gr,r1,w,wd4 with top card g6
    # Optimal play: g4 (enables g4 -> g3 -> gr -> wr -> r1 -> wd4)
    state = {
      'type' => 'request_action',
      'state' => {
        'hand' => %w[g3 g4 gr r1 w wd4],
        'top_card' => 'g6',
        'playable_cards' => %w[g3 g4 gr],
        'opponent_hand_sizes' => [2], # Opponent has 2 cards
        'war_cards_to_draw' => 0,
        'available_actions' => ['play']
      }
    }

    # Capture the agent's decision
    action = @agent.send(:decide_action, state['state'])

    assert_equal 'play', action['action']
    assert_equal 'g4', action['card'], 'Should play g4 to enable longest chain'
  end

  def test_wild_card_conservation
    # Case: Should not waste wd4 when other options are available
    action = simulate_agent_decision(
      %w[b2 b5 b5 b6 wd4 y3],
      'g8',
      ['wd4'] # Only wd4 is playable
    )

    assert_equal 'play', action['action']
    assert_equal 'wd4', action['card'], "Should play wd4 when it's the only option"

    # But when we have other options...
    action = simulate_agent_decision(
      %w[b2 b5 b5 b6 wd4 y3],
      'b8',
      %w[b2 b5 b6 wd4]
    )

    assert_equal 'play', action['action']
    refute_equal 'wd4', action['card'], 'Should NOT play wd4 when other cards are available'
  end

  def test_isolated_number_preference
    # Case: b9 is isolated (no other 9s), br is action card
    # Should prefer b9 over br when opponent has many cards
    action = simulate_agent_decision(
      ['b+2', 'b9', 'br', 'g0', 'g6', 'g6', 'y1', 'y8'],
      'b6',
      ['b+2', 'b9', 'br'],
      [5] # Opponent has 5 cards
    )

    assert_equal 'play', action['action']
    assert_equal 'b9', action['card'], 'Should play isolated number card b9'
  end

  def test_war_reverse_counter
    # Case: In a +2 war, should play reverse if available
    action = simulate_agent_decision(
      ['br', 'g+2', 'r3', 'y7'],
      'b+2',
      ['br', 'g+2'],
      [3],
      2
    )

    assert_equal 'play', action['action']
    assert_equal 'br', action['card'], 'Should play reverse to counter war'
  end

  def test_opponent_one_card_disruption
    # Case: Opponent has 1 card - maximum disruption
    action = simulate_agent_decision(
      ['b3', 'b+2', 'bs', 'wd4', 'y5'],
      'b7',
      ['b3', 'b+2', 'bs', 'wd4'],
      [1] # Opponent has 1 card!
    )

    assert_equal 'play', action['action']
    assert_includes ['b+2', 'bs'], action['card'], 'Should play disruptive card when opponent has 1 card'
  end

  def test_safe_play_when_low_cards
    # Case: We have only 2 cards - play safe
    action = simulate_agent_decision(
      %w[b9 wd4],
      'b3',
      %w[b9 wd4],
      [5]
    )

    assert_equal 'play', action['action']
    assert_equal 'b9', action['card'], "Should play number card when we're low"
  end

  def test_action_card_timing
    # Case: Don't waste action cards when opponent has many cards
    action = simulate_agent_decision(
      %w[b3 bs g2 g4 r7],
      'b9',
      %w[b3 bs],
      [7] # Opponent has 7 cards
    )

    assert_equal 'play', action['action']
    assert_equal 'b3', action['card'], 'Should save action cards when opponent has many cards'
  end

  def test_draw_decision
    # Case: No playable cards - must draw
    action = simulate_agent_decision(
      %w[r3 r7 g2],
      'y5',
      [],
      [4]
    )

    assert_equal 'draw', action['action'], 'Should draw when no cards are playable'
  end

  def test_wild_color_selection
    # Case: Playing wild card - should pick color we have most of
    action = simulate_agent_decision(
      %w[b3 b7 b9 g2 r1 w],
      'y5',
      ['w'],
      [3]
    )

    assert_equal 'play', action['action']
    assert_equal 'w', action['card']
    assert_equal 'blue', action['wild_color'], 'Should pick blue (have 3 blue cards)'
  end

  def test_defensive_wd4_when_opponent_uno
    # Case: We have 7 cards, opponent has 1 card - must play wd4 to prevent loss
    action = simulate_agent_decision(
      %w[b2 b5 g3 g7 r1 wd4 y8],
      'g9',
      %w[g3 g7 wd4], # We have color matches but should play wd4
      [1] # CRITICAL: Opponent has UNO!
    )

    assert_equal 'play', action['action']
    assert_equal 'wd4', action['card'], 'Must play wd4 to prevent opponent from winning'
  end

  def test_defensive_plus2_when_opponent_uno
    # Case: We have 7 cards, opponent has 1 card, no wd4 - must play +2
    action = simulate_agent_decision(
      ['b+2', 'b3', 'b7', 'g4', 'r8', 'y2', 'y9'],
      'b6',
      ['b+2', 'b3', 'b7'], # Have multiple options
      [1] # CRITICAL: Opponent has UNO!
    )

    assert_equal 'play', action['action']
    assert_equal 'b+2', action['card'], 'Must play +2 to prevent opponent from winning'
  end

  def test_prefer_plus2_over_wd4_for_defense
    # Case: When we have both +2 and wd4, prefer +2 (it's checked first)
    action = simulate_agent_decision(
      ['b+2', 'b5', 'g8', 'r3', 'wd4', 'y1', 'y7'],
      'b9',
      ['b+2', 'b5', 'wd4'],
      [1] # Opponent has UNO!
    )

    assert_equal 'play', action['action']
    assert_equal 'b+2', action['card'], 'Should prefer +2 over wd4 for disruption'
  end

  def test_winning_sequence_with_skips
    # Scenario: We have 5 cards with multiple skips that can win in sequence
    # Hand: b9, g4, gs, gs, bs with top card b4
    # Optimal play: b9 -> (opponent plays g9) -> g4 -> gs -> bs -> gs -> win!

    # First decision with hand size 5
    action = simulate_agent_decision(
      %w[b9 g4 gs gs bs],
      'b4',
      %w[b9 bs], # Can play b9 or bs
      [5]
    )

    # With 5 cards and opponent having 5, should prefer b9 (isolated number)
    assert_equal 'play', action['action']
    assert_equal 'b9', action['card'], 'Should play b9 (isolated number)'

    # Scenario continues: opponent plays g9, now we're down to 4 cards
    action2 = simulate_agent_decision(
      %w[g4 gs gs bs],
      'g9',
      %w[g4 gs], # Can play g4 or gs
      [5] # They still have 5 after drawing and playing
    )

    # With 4 cards, skip cards become very valuable
    # Agent should recognize the skip chain potential
    assert_equal 'play', action2['action']
    # Could play either g4 or gs here - both are reasonable
    assert_includes %w[g4 gs], action2['card'], 'Should play a green card'

    # If we played g4, opponent might play g5, then we have winning sequence
    if action2['card'] == 'g4'
      # Test the skip chain
      action3 = simulate_agent_decision(
        %w[gs gs bs],
        'g5', # Opponent played g5
        ['gs'],
        [5]
      )

      assert_equal 'play', action3['action']
      assert_equal 'gs', action3['card'], 'Should play gs to skip'
    else
      # We played gs first, which also works
      action3 = simulate_agent_decision(
        %w[g4 gs bs],
        'gs', # We get another turn after skip
        %w[g4 gs bs],
        [5]
      )

      # With multiple skips, should continue skip chain
      assert_equal 'play', action3['action']
      assert_includes %w[gs bs], action3['card'], 'Should continue skip chain'
    end
  end

  def test_skip_chain_endgame
    # Specific test: with 3 cards left (2 skips + 1 number), recognize winning pattern
    # Hand: gs, bs, g4 with top card gs (after we just played a skip)
    action = simulate_agent_decision(
      %w[g4 gs bs],
      'gs', # We just played green skip
      %w[g4 gs bs], # All playable
      [5],
      0
    )

    # Should prefer skip cards to maintain control
    assert_equal 'play', action['action']
    # Both gs and bs are good choices (both skips)
    assert_includes %w[gs bs], action['card'], 'Should play a skip card to maintain control'
  end

  def test_massive_skip_chain_opportunity
    # Test case: We have 10 cards with 8 skip cards that can win in one turn
    # Top card g9, hand: g8, g8, gs, gs, bs, bs, ys, ys, rs, rs
    # Optimal play: gs -> bs -> bs -> ys -> ys -> rs -> rs -> g8g8 (double play)
    action = simulate_agent_decision(
      %w[g8 g8 gs gs bs bs ys ys rs rs],
      'g9',
      %w[g8 gs], # Can play g8 or gs
      [7]
    )

    assert_equal 'play', action['action']
    # Should recognize the massive skip chain opportunity
    assert_equal 'gs', action['card'], 'Should play gs to start the skip chain'
  end

  def test_winning_skip_chain_three_cards
    # Test case: We have 3 cards and can win in one turn with skip chain
    # Opponent has 1 card, top card is g8. We have gs, ys, wd4.
    # Optimal play: gs -> ys -> wd4 (win in one turn!)
    action = simulate_agent_decision(
      %w[gs ys wd4],
      'g8',
      %w[gs wd4], # Can play gs or wd4
      [1] # Opponent has UNO
    )

    assert_equal 'play', action['action']
    # Should recognize we can win in one turn: gs -> ys -> wd4
    assert_equal 'gs', action['card'], 'Should play gs to start winning sequence'
  end

  def test_save_skips_when_no_danger
    # Test case: We have 4 cards with skips, opponent has many cards (no danger)
    # Top card is bs. We have b2, b8, gs, gs.
    # Should play b8 (then b2), saving skips for later
    action = simulate_agent_decision(
      %w[b2 b8 gs gs],
      'bs',
      %w[b2 b8 gs],
      [3] # Opponent has many cards - no immediate danger
    )

    assert_equal 'play', action['action']
    # Should play number cards first when no danger, save skips for later
    assert_includes %w[b2 b8], action['card'], 'Should play number card when no danger'
    refute_equal 'gs', action['card'], 'Should NOT play skip when opponent has many cards'
  end

  private

  def simulate_agent_decision(hand, top_card, playable_cards, opponent_cards = [7], war_cards = 0)
    state = {
      'hand' => hand,
      'top_card' => top_card,
      'playable_cards' => playable_cards,
      'opponent_hand_sizes' => opponent_cards,
      'war_cards_to_draw' => war_cards,
      'available_actions' => playable_cards.empty? ? ['draw'] : ['play']
    }

    @agent.send(:decide_action, state)
  end
end

# Run the test if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  # Run tests with verbose output
  Minitest.run
end
