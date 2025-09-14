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
          card_count: player.hand.size
        }
      end
    end

    def calculate_available_actions(game)
      actions = []
      already_picked = game.instance_variable_get(:@already_picked) || false
      stacked_cards = game.instance_variable_get(:@stacked_cards) || 0

      if already_picked
        # After drawing a card, only the picked card can be played; otherwise pass.
        picked_card = game.instance_variable_get(:@picked_card)
        actions << 'play' if picked_card && game.send(:playable_now?, picked_card)
        actions << 'pass'
        return actions
      end

      # Normal turn (haven't drawn yet)
      actions << 'play'
      actions << 'draw' if stacked_cards == 0
      actions << 'pass' if stacked_cards > 0
      actions
    end

    def calculate_playable_cards(game, player)
      already_picked = game.instance_variable_get(:@already_picked) || false
      if already_picked
        picked_card = game.instance_variable_get(:@picked_card)
        return [] unless picked_card && game.send(:playable_now?, picked_card)
        return [serialize_card(picked_card)]
      end

      # Normal turn: return all playable cards from hand
      player.hand.each_with_object([]) do |card, arr|
        arr << serialize_card(card) if game.send(:playable_now?, card)
      end
    end
  end
end
