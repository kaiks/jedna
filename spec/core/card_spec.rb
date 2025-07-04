require 'spec_helper'

RSpec.describe Jedna::Card do
  describe '#initialize' do
    it 'creates a valid card with color and figure' do
      card = Jedna::Card.new(:red, 5)
      expect(card.color).to eq(:red)
      expect(card.figure).to eq(5)
    end
    
    it 'creates a wild card' do
      card = Jedna::Card.new(:wild, 'wild')
      expect(card.color).to eq(:wild)
      expect(card.figure).to eq('wild')
    end
    
    it 'creates a wild draw four card' do
      card = Jedna::Card.new(:wild, 'wild+4')
      expect(card.color).to eq(:wild)
      expect(card.figure).to eq('wild+4')
    end
    
    it 'throws for invalid color' do
      # The code uses throw with a string, which is unusual but that's how it works
      expect { Jedna::Card.new(:purple, 5) }.to raise_error(UncaughtThrowError)
    end
    
    it 'throws for invalid figure' do
      # The code uses throw with a string, which is unusual but that's how it works
      expect { Jedna::Card.new(:red, 10) }.to raise_error(UncaughtThrowError)
    end
    
    it 'downcases string inputs' do
      card = Jedna::Card.new(:red, 'SKIP')
      expect(card.color).to eq(:red)
      expect(card.figure).to eq('skip')
    end
  end
  
  describe '.parse' do
    context 'regular cards' do
      it 'parses number cards' do
        card = Jedna::Card.parse('r5')
        expect(card.color).to eq(:red)
        expect(card.figure).to eq(5)
      end
      
      it 'parses action cards' do
        card = Jedna::Card.parse('bs')
        expect(card.color).to eq(:blue)
        expect(card.figure).to eq('skip')
      end
      
      it 'parses +2 cards' do
        card = Jedna::Card.parse('g+2')
        expect(card.color).to eq(:green)
        expect(card.figure).to eq('+2')
      end
      
      it 'parses reverse cards' do
        card = Jedna::Card.parse('yr')
        expect(card.color).to eq(:yellow)
        expect(card.figure).to eq('reverse')
      end
    end
    
    context 'wild cards' do
      it 'parses wild card without color' do
        # The parsing code expects at least 2 characters for wild cards
        # A plain 'w' would need special handling
        card = Jedna::Card.parse('ww')
        expect(card.color).to eq(:wild)
        expect(card.figure).to eq('wild')
      end
      
      it 'parses wild card with color' do
        card = Jedna::Card.parse('wr')
        expect(card.color).to eq(:red)
        expect(card.figure).to eq('wild')
      end
      
      it 'parses wild draw four without color' do
        card = Jedna::Card.parse('wd4')
        expect(card.color).to eq(:wild)
        expect(card.figure).to eq('wild+4')
      end
      
      it 'parses wild draw four with color' do
        card = Jedna::Card.parse('wd4b')
        expect(card.color).to eq(:blue)
        expect(card.figure).to eq('wild+4')
      end
    end
  end
  
  describe '#plays_after?' do
    let(:red5) { Jedna::Card.new(:red, 5) }
    let(:red9) { Jedna::Card.new(:red, 9) }
    let(:blue5) { Jedna::Card.new(:blue, 5) }
    let(:green7) { Jedna::Card.new(:green, 7) }
    let(:wild) { Jedna::Card.new(:wild, 'wild') }
    let(:wild_red) { Jedna::Card.new(:red, 'wild') }
    
    it 'allows same color play' do
      expect(red9).to be_playable_after(red5)
    end
    
    it 'allows same number play' do
      expect(blue5).to be_playable_after(red5)
    end
    
    it 'does not allow different color and number' do
      expect(green7).not_to be_playable_after(red5)
    end
    
    it 'allows wild cards to play on anything' do
      expect(wild).to be_playable_after(red5)
    end
    
    it 'allows any card to play on wild with color' do
      expect(red5).to be_playable_after(wild_red)
      expect(red9).to be_playable_after(wild_red)
    end
    
    it 'allows cards to play on uncolored wild' do
      expect(red5).to be_playable_after(wild)
    end
  end
  
  describe '#is_offensive?' do
    it 'returns true for +2 cards' do
      card = Jedna::Card.new(:red, '+2')
      expect(card.is_offensive?).to be true
    end
    
    it 'returns true for wild+4 cards' do
      card = Jedna::Card.new(:wild, 'wild+4')
      expect(card.is_offensive?).to be true
    end
    
    it 'returns false for regular cards' do
      card = Jedna::Card.new(:red, 5)
      expect(card.is_offensive?).to be false
    end
    
    it 'returns false for skip/reverse' do
      expect(Jedna::Card.new(:red, 'skip').is_offensive?).to be false
      expect(Jedna::Card.new(:red, 'reverse').is_offensive?).to be false
    end
  end
  
  describe '#offensive_value' do
    it 'returns 2 for +2 cards' do
      card = Jedna::Card.new(:red, '+2')
      expect(card.offensive_value).to eq(2)
    end
    
    it 'returns 4 for wild+4 cards' do
      card = Jedna::Card.new(:wild, 'wild+4')
      expect(card.offensive_value).to eq(4)
    end
    
    it 'returns 0 for non-offensive cards' do
      expect(Jedna::Card.new(:red, 5).offensive_value).to eq(0)
      expect(Jedna::Card.new(:red, 'skip').offensive_value).to eq(0)
    end
  end
  
  describe '#is_war_playable?' do
    it 'returns true for +2 cards' do
      expect(Jedna::Card.new(:red, '+2').is_war_playable?).to be true
    end
    
    it 'returns true for wild+4 cards' do
      expect(Jedna::Card.new(:wild, 'wild+4').is_war_playable?).to be true
    end
    
    it 'returns true for reverse cards' do
      expect(Jedna::Card.new(:red, 'reverse').is_war_playable?).to be true
    end
    
    it 'returns false for regular number cards' do
      expect(Jedna::Card.new(:red, 5).is_war_playable?).to be false
    end
    
    it 'returns false for skip cards' do
      expect(Jedna::Card.new(:red, 'skip').is_war_playable?).to be false
    end
  end
  
  describe '#value' do
    it 'returns face value for number cards' do
      (0..9).each do |num|
        card = Jedna::Card.new(:red, num)
        expect(card.value).to eq(num)
      end
    end
    
    it 'returns 20 for action cards' do
      expect(Jedna::Card.new(:red, 'skip').value).to eq(20)
      expect(Jedna::Card.new(:red, 'reverse').value).to eq(20)
      expect(Jedna::Card.new(:red, '+2').value).to eq(20)
    end
    
    it 'returns 50 for wild cards' do
      expect(Jedna::Card.new(:wild, 'wild').value).to eq(50)
      expect(Jedna::Card.new(:wild, 'wild+4').value).to eq(50)
    end
  end
  
  describe '#set_wild_color / #unset_wild_color' do
    let(:wild) { Jedna::Card.new(:wild, 'wild') }
    let(:wild4) { Jedna::Card.new(:wild, 'wild+4') }
    let(:regular) { Jedna::Card.new(:red, 5) }
    
    it 'sets color for wild cards' do
      wild.set_wild_color(:red)
      expect(wild.color).to eq(:red)
    end
    
    it 'unsets color for wild cards' do
      wild.set_wild_color(:red)
      wild.unset_wild_color
      expect(wild.color).to eq(:wild)
    end
    
    it 'does not change color for regular cards' do
      regular.set_wild_color(:blue)
      expect(regular.color).to eq(:red)
    end
  end
  
  describe '#to_s' do
    it 'formats regular cards as color+figure' do
      expect(Jedna::Card.new(:red, 5).to_s).to eq('r5')
      expect(Jedna::Card.new(:blue, 'skip').to_s).to eq('bs')
    end
    
    it 'formats wild cards as figure+color' do
      expect(Jedna::Card.new(:wild, 'wild').to_s).to eq('w')
      expect(Jedna::Card.new(:wild, 'wild+4').to_s).to eq('wd4')
    end
    
    it 'includes color for wild cards when set' do
      wild = Jedna::Card.new(:wild, 'wild')
      wild.set_wild_color(:red)
      expect(wild.to_s).to eq('wr')
    end
  end
  
  
  describe '#special_card?' do
    it 'returns true for wild cards' do
      expect(Jedna::Card.new(:wild, 'wild').special_card?).to be true
      expect(Jedna::Card.new(:wild, 'wild+4').special_card?).to be true
    end
    
    it 'returns false for regular cards' do
      expect(Jedna::Card.new(:red, 5).special_card?).to be false
      expect(Jedna::Card.new(:red, 'skip').special_card?).to be false
    end
  end
  
  describe '#==' do
    it 'considers cards with same color and figure equal' do
      card1 = Jedna::Card.new(:red, 5)
      card2 = Jedna::Card.new(:red, 5)
      expect(card1).to eq(card2)
    end
    
    it 'considers cards with different attributes not equal' do
      expect(Jedna::Card.new(:red, 5)).not_to eq(Jedna::Card.new(:blue, 5))
      expect(Jedna::Card.new(:red, 5)).not_to eq(Jedna::Card.new(:red, 6))
    end
  end
end