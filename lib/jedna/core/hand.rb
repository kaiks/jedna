require_relative 'card'

module Jedna
  class Hand < Array
    def <<(cards)
      push(cards)
      flatten!
    end
  
    def add_card(card)
      throw 'Not a card. Cant add' unless card.is_a? Card
      push(card)
    end
  
    def value
      return 0 if size == 0
      map(&:value).reduce(:+)
    end
  
    def to_s
      map(&:to_s).reduce { |old, new| old += " #{new}" }
    end
  
  
    def find_card(card_string)
      detect { |card| card.to_s == card_string }
    end
  
  
    def reset_wilds
      each(&:unset_wild_color)
    end
  
    def add_random(n)
      n.times do
        color_index = rand(4)
        figure_index = rand(15)
  
        color_index = 4 if figure_index > 12 # in case of wild figure
  
        color = Jedna::COLORS[color_index]
        figure = Jedna::FIGURES[figure_index]
  
        card = Card.new(color, figure)
        add_card(card)
      end
    end
  
    def destroy(card)
      throw 'Deleting wild card? Something went wrong' if card.color == :wild
      delete_at(index(card) || length)
    end
  
    def playable_after(card)
      select { |x| x.plays_after? card }
    end
  
    def colors
      map(&:color).uniq
    end
  
    def select(&block)
      Hand.new(super(&block))
    end
  
    def reverse
      Hand.new(super)
    end
  
    def reverse!
      super
    end
  
    # Jedna::COLORS[color]
    def of_color(color)
      select { |card| card.color == color }
    end
  end
end
