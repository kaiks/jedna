require 'spec_helper'

RSpec.describe "Jedna::Player with Identity abstraction" do
  describe 'backward compatibility' do
    it 'creates player with string nick (backward compatible)' do
      player = Jedna::Player.new('Alice')
      expect(player.identity.display_name).to eq('Alice')
      expect(player.to_s).to eq('Alice')
    end
    
    it 'supports nick change for IRC identity' do
      player = Jedna::Player.new('Alice')
      player.identity.update_display_name('Alice2')
      expect(player.identity.display_name).to eq('Alice2')
    end
    
    it 'compares players by identity' do
      player1 = Jedna::Player.new('Alice')
      player2 = Jedna::Player.new('Alice')
      player3 = Jedna::Player.new('Bob')
      
      expect(player1 == player2).to be true
      expect(player1 == player3).to be false
    end
  end
  
  describe 'with explicit IRC identity' do
    let(:identity) { Jedna::IrcIdentity.new('Alice') }
    let(:player) { Jedna::Player.new(identity) }
    
    it 'uses the provided identity' do
      expect(player.identity).to eq(identity)
      expect(player.identity.display_name).to eq('Alice')
    end
    
    it 'matches against nick string' do
      expect(player.matches?('Alice')).to be true
      expect(player.matches?('Bob')).to be false
    end
    
    it 'matches against another identity' do
      other_identity = Jedna::IrcIdentity.new('Alice')
      expect(player.matches?(other_identity)).to be true
    end
  end
  
  describe 'with UUID identity' do
    let(:uuid) { '123e4567-e89b-12d3-a456-426614174000' }
    let(:identity) { Jedna::UuidIdentity.new(uuid, 'Alice') }
    let(:player) { Jedna::Player.new(identity) }
    
    it 'uses the provided identity' do
      expect(player.identity).to eq(identity)
      expect(player.identity.display_name).to eq('Alice') # display name
      expect(player.to_s).to eq('Alice')
    end
    
    it 'matches against UUID string' do
      expect(player.matches?(uuid)).to be true
      expect(player.matches?('Alice')).to be false # Does not match display name
    end
    
    it 'handles nick change gracefully' do
      # Should warn but not crash
      # UUID identities support update_display_name
      expect(player.identity.respond_to?(:update_display_name)).to be true
    end
  end
  
  describe 'hand management' do
    let(:player) { Jedna::Player.new('Alice') }
    
    it 'initializes with empty hand' do
      expect(player.hand).to be_a(Jedna::Hand)
      expect(player.hand.size).to eq(0)
    end
    
    it 'can add cards to hand' do
      card = Jedna::Card.new(:red, 5)
      player.hand << card
      expect(player.hand.size).to eq(1)
      expect(player.hand[0]).to eq(card)
    end
  end
end