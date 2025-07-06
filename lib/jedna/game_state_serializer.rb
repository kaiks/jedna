module Jedna
  class GameStateSerializer
    def serialize_for_current_player(game)
      return nil unless game.started?
      
      current_player = game.players[0]
      
      {
        type: 'request_action',
        state: {
          your_id: current_player.identity.id,
          hand: serialize_hand(current_player.hand),
          top_card: serialize_card(game.top_card),
          game_state: serialize_game_state(game.game_state),
          stacked_cards: game.instance_variable_get(:@stacked_cards) || 0,
          already_picked: game.instance_variable_get(:@already_picked) || false,
          picked_card: serialize_card(game.instance_variable_get(:@picked_card)),
          other_players: serialize_other_players(game.players[1..-1]),
          available_actions: calculate_available_actions(game),
          playable_cards: calculate_playable_cards(game, current_player)
        }
      }
    end
    
    def serialize_notification(message)
      {
        type: 'notification',
        message: message
      }
    end
    
    def serialize_error(message)
      {
        type: 'error',
        message: message
      }
    end
    
    def serialize_game_end(game, winner)
      scores = {}
      game.players.each do |player|
        scores[player.identity.id] = player.hand.value
      end
      
      {
        type: 'game_end',
        winner: winner.identity.id,
        scores: scores
      }
    end
    
    private
    
    def serialize_hand(hand)
      hand.map { |card| serialize_card(card) }
    end
    
    def serialize_card(card)
      return nil if card.nil?
      card.to_s
    end
    
    def serialize_game_state(state)
      case state
      when 0 then 'off'
      when 1 then 'normal'
      when 2 then 'war_+2'
      when 3 then 'war_wd4'
      else 'unknown'
      end
    end
    
    def serialize_other_players(players)
      players.map do |player|
        {
          id: player.identity.id,
          cards: player.hand.size
        }
      end
    end
    
    def calculate_available_actions(game)
      actions = []
      already_picked = game.instance_variable_get(:@already_picked) || false
      stacked_cards = game.instance_variable_get(:@stacked_cards) || 0
      
      # You can always try to play a card
      actions << 'play'
      
      # You can draw if you haven't already and there are no stacked cards
      if !already_picked && stacked_cards == 0
        actions << 'draw'
      end
      
      # You can pass if you've already picked or there are stacked cards to draw
      if already_picked || stacked_cards > 0
        actions << 'pass'
      end
      
      actions
    end
    
    def calculate_playable_cards(game, player)
      playable = []
      
      player.hand.each do |card|
        # Use the game's playable_now? method to check if card can be played
        if game.send(:playable_now?, card)
          playable << serialize_card(card)
        end
      end
      
      playable
    end
  end
end