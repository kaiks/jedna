# frozen_string_literal: true

require_relative 'game_state_serializer'
require_relative 'action_result'
require_relative 'protocol_card_lookup'

module Jedna
  # Applies one action from the automated-play protocol to a game.
  class ActionExecutor
    WILD_COLORS = %w[red green blue yellow].freeze
    ACTION_METHODS = { 'play' => :execute_play, 'draw' => :execute_draw, 'pass' => :execute_pass }.freeze

    def initialize(game)
      @game = game
      @serializer = GameStateSerializer.new
    end

    def execute(action = nil, player: nil, **action_fields)
      action ||= action_fields unless action_fields.empty?
      validation = validate_request(action, player)
      return validation if validation

      current_player = @game.players.first
      action_name = value(action, 'action')
      state = @serializer.serialize_for_current_player(@game).fetch(:state)
      validation = validate_availability(state, action_name)
      return validation if validation

      send(ACTION_METHODS.fetch(action_name), action, current_player, state)
    end

    private

    def execute_play(action, player, state)
      card_code = value(action, 'card')
      card = ProtocolCardLookup.find(player.hand, card_code)
      wild_color = value(action, 'wild_color')
      double_play = value(action, 'double_play')
      validation = validate_play(action, player, state, card)
      return validation if validation

      card.set_wild_color(wild_color) if card.wild?
      played = @game.player_card_play(player, card, double_play == true)
      return failure('action_rejected', 'The game rejected the play', 'play') unless played

      success('play')
    end

    def execute_draw(*)
      @game.pick_single
      success('draw')
    end

    def execute_pass(*)
      @game.turn_pass
      success('pass')
    end

    def validate_request(action, player)
      return failure('invalid_action', 'Action must be an object') unless action.is_a?(Hash)
      return failure('game_not_started', 'The game is not started') unless @game.started?
      if player && player != @game.players.first
        return failure('not_current_player', 'The player is not the current player')
      end

      action_name = value(action, 'action')
      return failure('invalid_action', 'Action must be play, draw, or pass') unless ACTION_METHODS.key?(action_name)

      nil
    end

    def validate_availability(state, action_name)
      return if state[:available_actions].include?(action_name)

      failure('action_unavailable', "#{action_name} is not available", action_name)
    end

    def validate_play(action, player, state, card)
      card_code = value(action, 'card')
      validation = validate_card(state, card_code, card)
      validation ||= validate_wild_color(card, value(action, 'wild_color')) if card
      validation ||= validate_double_play(player, card, value(action, 'double_play')) if card
      validation
    end

    def validate_card(state, card_code, card)
      return failure('card_required', 'Play requires a card', 'play') unless card_code.is_a?(String)
      unless state[:playable_cards].include?(card_code)
        return failure('card_not_playable', "#{card_code} is not playable", 'play')
      end
      return failure('card_not_in_hand', "#{card_code} is not in the player's hand", 'play') unless card

      nil
    end

    def validate_wild_color(card, wild_color)
      if card.wild?
        return failure('wild_color_required', 'Wild cards require wild_color', 'play') if wild_color.nil?
        unless WILD_COLORS.include?(wild_color.to_s)
          return failure('invalid_wild_color', "Invalid wild color: #{wild_color}", 'play')
        end
      elsif !wild_color.nil?
        return failure('unexpected_wild_color', 'wild_color is only valid for wild cards', 'play')
      end

      nil
    end

    def validate_double_play(player, card, double_play)
      unless [nil, true, false].include?(double_play)
        return failure('invalid_double_play', 'double_play must be true or false', 'play')
      end

      available = ProtocolCardLookup.double_play_available?(
        player.hand,
        card,
        already_picked: @game.already_picked
      )
      return unless double_play && !available

      failure('double_play_unavailable', 'A matching second card is not available', 'play')
    end

    def value(action, key)
      action[key] || action[key.to_sym]
    end

    def success(action)
      ActionResult.new(success: true, code: 'ok', message: nil, action: action)
    end

    def failure(code, message, action = nil)
      ActionResult.new(success: false, code: code, message: message, action: action)
    end
  end
end
