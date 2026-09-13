# frozen_string_literal: true

require_relative 'card'
require_relative 'hand'

module Jedna
  # An ordered deck that builds the standard card set and draws from the front.
  class CardStack < Hand
    def create_discard_pile
      @discard_pile = Hand.new
    end

    def fill
      Jedna::STANDARD_SHORT_FIGURES.each do |f|
        %w[r g b y].each do |c|
          self << Card.parse(c + f)
          self << Card.parse(c + f) if f != '0'
        end
      end

      4.times do
        self << Card.parse('ww')
        self << Card.parse('wd4')
      end

      self
    end

    # shuffle!

    def pick(count)
      to_return = CardStack.new(first(count))
      shift(count)
      to_return
    end
  end
end
