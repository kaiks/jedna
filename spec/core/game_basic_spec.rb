require 'spec_helper'

RSpec.describe "Jedna::Game basic functionality" do
  let(:game) { TestJednaGame.new('TestCreator', 1) }
  let(:alice) { Jedna::Player.new('Alice') }
  let(:bob) { Jedna::Player.new('Bob') }
  
  describe 'game setup and start' do
    it 'initializes with correct state' do
      expect(game.game_state).to eq(0)
      expect(game.players).to be_empty
      expect(game.creator).to eq('TestCreator')
    end
    
    it 'adds players and starts game' do
      game.add_player(alice)
      game.add_player(bob)
      
      expect(game.players.size).to eq(2)
      
      game.start_game
      
      expect(game.game_state).to eq(1)
      expect(game.top_card).to be_a(Jedna::Card)
      expect(alice.hand.size).to eq(7)
      expect(bob.hand.size).to eq(7)
    end
  end
  
  describe 'basic card play' do
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
      # Ensure known state
      game.instance_variable_set(:@players, [alice, bob])
      game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 5))
    end
    
    it 'allows valid card play' do
      # Give alice a matching card plus extras so game doesn't end
      card = Jedna::Card.new(:red, 7)
      alice.hand = Jedna::Hand.new
      alice.hand << card
      alice.hand << Jedna::Card.new(:blue, 5)  # Extra cards so game continues
      alice.hand << Jedna::Card.new(:green, 3)
      
      result = game.player_card_play(alice, card)
      
      expect(result).to be true
      expect(game.top_card).to eq(card)
      expect(alice.hand.size).to eq(2)  # Should have 2 cards left
      expect(game.players[0]).to eq(bob) # Turn passed to bob
    end
    
    it 'rejects invalid card play' do
      # Give alice a non-matching card
      card = Jedna::Card.new(:blue, 9)
      alice.hand = Jedna::Hand.new
      alice.hand << card
      
      result = game.player_card_play(alice, card)
      
      expect(result).to be false
      expect(alice.hand).to include(card)
      expect(game.players[0]).to eq(alice) # Still alice's turn
    end
    
    it 'handles wild cards correctly' do
      # Give alice a wild card
      wild = Jedna::Card.new(:wild, 'wild')
      alice.hand = Jedna::Hand.new
      alice.hand << wild
      
      # Must set color before playing
      wild.set_wild_color(:blue)
      
      result = game.player_card_play(alice, wild)
      
      expect(result).to be true
      expect(game.top_card).to eq(wild)
      expect(game.top_card.color).to eq(:blue)
    end
  end
  
  describe 'special cards' do
    let(:charlie) { Jedna::Player.new('Charlie') }
    
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.add_player(charlie)
      game.start_game
      game.instance_variable_set(:@players, [alice, bob, charlie])
      game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 5))
    end
    
    it 'skip card skips next player' do
      skip_card = Jedna::Card.new(:red, 'skip')
      alice.hand = Jedna::Hand.new
      alice.hand << skip_card
      alice.hand << Jedna::Card.new(:blue, 5)  # Extra cards so game continues
      alice.hand << Jedna::Card.new(:green, 3)
      
      game.player_card_play(alice, skip_card)
      
      expect(game.players[0]).to eq(charlie)
      expect(game.notifications.any? { |n| n.include?("was skipped") }).to be true
    end
    
    it 'reverse card reverses order' do
      reverse_card = Jedna::Card.new(:red, 'reverse')
      alice.hand = Jedna::Hand.new
      alice.hand << reverse_card
      alice.hand << Jedna::Card.new(:blue, 5)  # Extra cards so game continues
      alice.hand << Jedna::Card.new(:green, 3)
      
      # Before: [Alice, Bob, Charlie]
      game.player_card_play(alice, reverse_card)
      
      # After reverse and rotate: [Charlie, Bob, Alice]
      expect(game.players[0]).to eq(charlie)
      expect(game.notifications.any? { |n| n.include?("reversed") }).to be true
    end
    
    it '+2 card starts war' do
      draw2 = Jedna::Card.new(:red, '+2')
      alice.hand = Jedna::Hand.new
      alice.hand << draw2
      alice.hand << Jedna::Card.new(:blue, 5)  # Extra cards so game continues
      alice.hand << Jedna::Card.new(:green, 3)
      
      game.player_card_play(alice, draw2)
      
      expect(game.game_state).to eq(2)
      expect(game.instance_variable_get(:@stacked_cards)).to eq(2)
    end
  end
  
  describe 'war mechanics' do
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
      game.instance_variable_set(:@players, [alice, bob])
    end
    
    it 'allows stacking +2 cards' do
      # Alice plays +2
      draw2_1 = Jedna::Card.new(:red, '+2')
      alice.hand = Jedna::Hand.new
      alice.hand << draw2_1
      alice.hand << Jedna::Card.new(:blue, 5)  # Extra cards so game continues
      alice.hand << Jedna::Card.new(:green, 3)
      game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 5))
      
      game.player_card_play(alice, draw2_1)
      expect(game.game_state).to eq(2)
      
      # Bob can play another +2
      draw2_2 = Jedna::Card.new(:blue, '+2')
      bob.hand = Jedna::Hand.new
      bob.hand << draw2_2
      bob.hand << Jedna::Card.new(:yellow, 7)  # Extra cards
      
      result = game.player_card_play(bob, draw2_2)
      expect(result).to be true
      expect(game.instance_variable_get(:@stacked_cards)).to eq(4)
    end
    
    it 'forces draw when cannot respond to war' do
      # Set up +2 war
      game.instance_variable_set(:@game_state, 2)
      game.instance_variable_set(:@stacked_cards, 4)
      game.instance_variable_set(:@players, [bob, alice])
      
      initial_size = bob.hand.size
      game.turn_pass
      
      expect(bob.hand.size).to eq(initial_size + 4)
      expect(game.game_state).to eq(1) # Back to normal
    end
  end
  
  describe 'winning' do
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
      game.instance_variable_set(:@players, [alice, bob])
    end
    
    it 'detects when player wins' do
      # Give alice one card
      card = Jedna::Card.new(:red, 5)
      alice.hand = Jedna::Hand.new
      alice.hand << card
      
      # Bob has cards for scoring
      bob.hand = Jedna::Hand.new
      bob.hand << [Jedna::Card.new(:blue, 5), Jedna::Card.new(:green, 'skip')]
      
      game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 3))
      game.player_card_play(alice, card)
      
      expect(game.game_state).to eq(0) # Game ended
      score = game.instance_variable_get(:@total_score)
      expect(score).to eq(30) # Minimum score
    end
    
    it 'announces UNO at one card' do
      # Give alice two cards
      alice.hand = Jedna::Hand.new
      alice.hand << [Jedna::Card.new(:red, 5), Jedna::Card.new(:red, 7)]
      
      game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 3))
      game.player_card_play(alice, alice.hand[0])
      
      uno_notification = game.notifications.find { |n| n.include?("has just one card left") }
      expect(uno_notification).not_to be_nil
    end
  end
  
  describe 'pick and pass' do
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
      game.instance_variable_set(:@players, [alice, bob])
    end
    
    it 'allows picking a card' do
      initial_size = alice.hand.size
      game.pick_single
      
      expect(alice.hand.size).to eq(initial_size + 1)
      expect(game.instance_variable_get(:@already_picked)).to be true
    end
    
    it 'allows passing after pick' do
      game.pick_single
      game.turn_pass
      
      expect(game.players[0]).to eq(bob)
    end
    
    it 'requires pick before pass in normal state' do
      game.turn_pass
      expect(game.notifications.last).to include("pick a card first")
      expect(game.players[0]).to eq(alice) # Still alice's turn
    end
  end
end