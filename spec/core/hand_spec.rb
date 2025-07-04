require 'spec_helper'

RSpec.describe Jedna::Hand do
  let(:hand) { Jedna::Hand.new }
  let(:red5) { Jedna::Card.new(:red, 5) }
  let(:blue3) { Jedna::Card.new(:blue, 3) }
  let(:green_skip) { Jedna::Card.new(:green, 'skip') }
  let(:wild) { Jedna::Card.new(:wild, 'wild') }
  let(:wild4) { Jedna::Card.new(:wild, 'wild+4') }
  
  describe '#<<' do
    it 'adds a single card' do
      hand << red5
      expect(hand.size).to eq(1)
      expect(hand.first).to eq(red5)
    end
    
    it 'adds multiple cards as an array' do
      hand << [red5, blue3]
      expect(hand.size).to eq(2)
      expect(hand).to include(red5, blue3)
    end
    
    it 'flattens nested arrays' do
      hand << [red5]
      hand << [[blue3, green_skip]]
      expect(hand.size).to eq(3)
      expect(hand).to include(red5, blue3, green_skip)
    end
  end
  
  describe '#add_card' do
    it 'adds a card to the hand' do
      hand.add_card(red5)
      expect(hand).to include(red5)
    end
    
    it 'throws error for non-card objects' do
      expect { hand.add_card("not a card") }.to raise_error(UncaughtThrowError)
    end
  end
  
  describe '#value' do
    it 'returns 0 for empty hand' do
      expect(hand.value).to eq(0)
    end
    
    it 'calculates total value of cards' do
      hand << [red5, blue3]  # 5 + 3 = 8
      expect(hand.value).to eq(8)
    end
    
    it 'includes action card values' do
      hand << [red5, green_skip]  # 5 + 20 = 25
      expect(hand.value).to eq(25)
    end
    
    it 'includes wild card values' do
      hand << [red5, wild, wild4]  # 5 + 50 + 50 = 105
      expect(hand.value).to eq(105)
    end
  end
  
  describe '#to_s' do
    it 'returns string representation of cards' do
      hand << [red5, blue3]
      expect(hand.to_s).to eq("r5 b3")
    end
    
    it 'returns nil for empty hand' do
      expect(hand.to_s).to be_nil
    end
  end
  
  
  describe '#find_card' do
    before do
      hand << [red5, blue3, green_skip]
    end
    
    it 'finds card by string notation' do
      expect(hand.find_card('r5')).to eq(red5)
      expect(hand.find_card('b3')).to eq(blue3)
      expect(hand.find_card('gs')).to eq(green_skip)
    end
    
    it 'returns nil if card not found' do
      expect(hand.find_card('y7')).to be_nil
    end
  end
  
  describe '#reset_wilds' do
    it 'unsets color on wild cards' do
      wild.set_wild_color(:red)
      wild4.set_wild_color(:blue)
      hand << [wild, wild4, red5]
      
      hand.reset_wilds
      
      expect(wild.color).to eq(:wild)
      expect(wild4.color).to eq(:wild)
      expect(red5.color).to eq(:red) # Regular cards unchanged
    end
  end
  
  describe '#add_random' do
    it 'adds specified number of random cards' do
      hand.add_random(5)
      expect(hand.size).to eq(5)
    end
    
    it 'creates valid cards' do
      hand.add_random(10)
      hand.each do |card|
        expect(card).to be_a(Jedna::Card)
        expect(Jedna::COLORS).to include(card.color)
        expect(Jedna::FIGURES).to include(card.figure)
      end
    end
  end
  
  describe '#destroy' do
    before do
      hand << [red5, blue3, green_skip]
    end
    
    it 'removes the specified card' do
      hand.destroy(blue3)
      expect(hand).not_to include(blue3)
      expect(hand.size).to eq(2)
    end
    
    it 'throws error when destroying uncolored wild card' do
      # The check is for color == :wild, not for wild cards with color set
      hand << wild
      expect { hand.destroy(wild) }.to raise_error(UncaughtThrowError)
    end
    
    it 'handles destroying non-existent card' do
      yellow7 = Jedna::Card.new(:yellow, 7)
      expect { hand.destroy(yellow7) }.not_to raise_error
    end
  end
  
  describe '#playable_after' do
    let(:top_card) { red5 }
    
    before do
      hand << [
        red5,                    # Same card
        Jedna::Card.new(:red, 9),    # Same color
        Jedna::Card.new(:blue, 5),   # Same number
        Jedna::Card.new(:yellow, 7), # Different
        wild                     # Wild card
      ]
    end
    
    it 'returns cards playable after given card' do
      playable = hand.playable_after(top_card)
      expect(playable.size).to eq(4) # All except yellow 7
      expect(playable).not_to include(Jedna::Card.new(:yellow, 7))
    end
    
    it 'returns Jedna::Hand instance' do
      expect(hand.playable_after(top_card)).to be_a(Jedna::Hand)
    end
  end
  
  describe '#colors' do
    it 'returns unique colors in hand' do
      hand << [
        Jedna::Card.new(:red, 5),
        Jedna::Card.new(:red, 9),
        Jedna::Card.new(:blue, 3),
        Jedna::Card.new(:green, 'skip')
      ]
      expect(hand.colors).to contain_exactly(:red, :blue, :green)
    end
    
    it 'returns empty array for empty hand' do
      expect(hand.colors).to be_empty
    end
  end
  
  describe '#select' do
    before do
      hand << [red5, blue3, green_skip, wild]
    end
    
    it 'returns Jedna::Hand instance' do
      result = hand.select { |card| card.color == :red }
      expect(result).to be_a(Jedna::Hand)
    end
    
    it 'filters cards by condition' do
      red_cards = hand.select { |card| card.color == :red }
      expect(red_cards.size).to eq(1)
      expect(red_cards.first).to eq(red5)
    end
  end
  
  describe '#reverse' do
    before do
      hand << [red5, blue3, green_skip]
    end
    
    it 'returns reversed Jedna::Hand instance' do
      reversed = hand.reverse
      expect(reversed).to be_a(Jedna::Hand)
      expect(reversed.to_a).to eq([green_skip, blue3, red5])
    end
    
    it 'does not modify original hand' do
      original_first = hand.first
      hand.reverse
      expect(hand.first).to eq(original_first)
    end
  end
  
  describe '#reverse!' do
    before do
      hand << [red5, blue3, green_skip]
    end
    
    it 'reverses hand in place' do
      hand.reverse!
      expect(hand.first).to eq(green_skip)
      expect(hand.last).to eq(red5)
    end
  end
  
  describe '#of_color' do
    before do
      hand << [
        Jedna::Card.new(:red, 5),
        Jedna::Card.new(:red, 9),
        Jedna::Card.new(:blue, 3),
        wild
      ]
    end
    
    it 'returns cards of specified color' do
      red_cards = hand.of_color(:red)
      expect(red_cards.size).to eq(2)
      expect(red_cards).to all(have_attributes(color: :red))
    end
    
    it 'returns Jedna::Hand instance' do
      expect(hand.of_color(:red)).to be_a(Jedna::Hand)
    end
    
    it 'returns empty Jedna::Hand for non-existent color' do
      expect(hand.of_color(:yellow).size).to eq(0)
    end
  end
  
  
  describe 'Array inheritance' do
    it 'supports array methods' do
      hand << [red5, blue3, green_skip]
      expect(hand.size).to eq(3)
      expect(hand[0]).to eq(red5)
      expect(hand.last).to eq(green_skip)
      expect(hand.map(&:color)).to eq([:red, :blue, :green])
    end
  end
end