# frozen_string_literal: true

require_relative 'card_stack'

module Jedna
  # A named default draw deck. CardStack remains available for custom stacks.
  class Deck < CardStack
    def generate_default_deck
      clear
      fill
    end
  end
end
