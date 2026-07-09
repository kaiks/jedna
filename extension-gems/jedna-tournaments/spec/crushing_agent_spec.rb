# frozen_string_literal: true

require 'spec_helper'
require_relative '../examples/crushing_agent'

module CrushingAgentSpecHelpers
  def state(hand:, playable:, already_picked: false)
    {
      'hand' => hand,
      'playable_cards' => playable,
      'available_actions' => %w[play draw],
      'already_picked' => already_picked,
      'top_card' => 'r3',
      'other_players' => [{ 'id' => 'opponent', 'card_count' => 7 }]
    }
  end
end

RSpec.describe CrushingDecider do
  include CrushingAgentSpecHelpers

  it 'prioritizes an available duplicate play' do
    action = described_class.new(state(hand: %w[r5 r5 b7], playable: %w[r5])).decide

    expect(action).to eq('action' => 'play', 'card' => 'r5', 'double_play' => true)
  end

  it 'does not double-play after drawing' do
    action = described_class.new(
      state(hand: %w[r5 r5 b7], playable: %w[r5], already_picked: true)
    ).decide

    expect(action).not_to include('double_play')
  end

  it 'keeps the advantageous single-skip turn in a two-player game' do
    action = described_class.new(state(hand: %w[rs rs r7], playable: %w[rs r7])).decide

    expect(action['card']).to eq('rs')
    expect(action).not_to include('double_play')
  end

  it 'pressures an opponent at one card' do
    current_state = state(hand: %w[r5 r5 wd4], playable: %w[r5 wd4])
    current_state['other_players'][0]['card_count'] = 1

    action = described_class.new(current_state).decide

    expect(action).to include('card' => 'wd4')
  end
end
