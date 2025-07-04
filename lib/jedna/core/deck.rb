module Jedna
  class Deck
    def generate_default_deck
      deck = []
      standard_colors.each do |color|
        standard_figures.each do |figure|
          deck += Card.new(color, figure)
        end
      end
  
      deck += deck
  
      deck.find
    end
  end
end
