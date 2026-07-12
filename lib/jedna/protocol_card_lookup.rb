# frozen_string_literal: true

module Jedna
  # Resolves canonical protocol card codes against the mutable cards in a hand.
  module ProtocolCardLookup
    module_function

    def find(hand, card_code)
      case card_code
      when 'w'
        hand.find { |card| card.figure == 'wild' }
      when 'wd4'
        hand.find { |card| card.figure == 'wild+4' }
      else
        hand.find_card(card_code)
      end
    end

    def double_play_available?(hand, card, already_picked:)
      return false if already_picked

      hand.count { |candidate| matching?(candidate, card) } >= 2
    end

    def matching?(candidate, card)
      return candidate.figure == card.figure if card.wild?

      candidate.to_s == card.to_s
    end
    private_class_method :matching?
  end
end
