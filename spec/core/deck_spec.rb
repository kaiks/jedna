# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Jedna::Deck do
  describe '#generate_default_deck' do
    it 'replaces its contents with a standard 108-card deck' do
      deck = described_class.new([Jedna::Card.new(:red, 5)])

      result = deck.generate_default_deck

      expect(result).to equal(deck)
      expect(deck.size).to eq(108)
      expect(deck.count { |card| card.figure == 'wild' }).to eq(4)
      expect(deck.count { |card| card.figure == 'wild+4' }).to eq(4)
    end
  end
end
