# #todo: irc format card display

# Define Jedna constants within the gem
module Jedna
  COLORS = %i[red green blue yellow wild].freeze
  SHORT_COLORS = %w[r g b y] + ['']
  STANDARD_FIGURES = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, '+2', 'reverse', 'skip'].freeze
  STANDARD_SHORT_FIGURES = %w[0 1 2 3 4 5 6 7 8 9 +2 r s].freeze
  SPECIAL_FIGURES = ['wild+4', 'wild'].freeze
  SPECIAL_SHORT_FIGURES = %w[wd4 w].freeze
  FIGURES = STANDARD_FIGURES + SPECIAL_FIGURES
  SHORT_FIGURES = STANDARD_SHORT_FIGURES + SPECIAL_SHORT_FIGURES

  def self.expand_color(short_color)
    short_color = short_color.downcase
    if SHORT_COLORS.member? short_color
      COLORS[SHORT_COLORS.find_index short_color]
    else
      throw 'not a valid color: ' + short_color.to_s
    end
  end

  def self.expand_figure(short_figure)
    short_figure = short_figure.downcase
    if SHORT_FIGURES.member? short_figure
      return FIGURES[SHORT_FIGURES.find_index short_figure]
    else
      if short_figure == '*'
        return 'wild'
      else
        throw 'not a valid figure: ' + short_figure.to_s
      end
    end
  end

  def self.random_color
    COLORS[rand 4]
  end

  class Card
  
    attr_reader :color, :figure
    attr_accessor :visited, :debug
  
    def self.debug(text)
      puts text if @debug
    end
  
    def initialize(color, figure)
      figure = figure.downcase if figure.is_a? String
      color = color.downcase if color.is_a? String
      throw 'Wrong color' unless Jedna::COLORS.include? color
      throw 'Wrong figure' unless Jedna::FIGURES.include? figure
  
      @color = color
      @figure = figure
      @visited = 0
      @debug = false
  
      throw "Not a valid card #{@color} #{@figure}" unless valid?
    end
  
    def <=>(card)
      @figure <=> card.figure && @color <=> card.color
    end
  
    def ==(card)
      (@figure.to_s == card.figure.to_s) && (@color == card.color)
    end
  
    def self.parse(card_text)
      card_text = card_text.downcase
      text_length = card_text.length
  
      return Card.parse_wild(card_text) if card_text[0] == 'w'
  
      short_color = card_text[0]
      short_figure = card_text[1..2]
  
      color = Jedna.expand_color(short_color)
      figure = Jedna.expand_figure(short_figure)
  
      Card.new(color, figure)
    end
  
    def self.parse_wild(card_text)
      card_text = card_text.downcase
      debug "parsing #{card_text}"
      if card_text[0..1].casecmp('ww').zero?
        debug '--WARNING: WILD CARD ' + card_text
        color = :wild
        short_figure = card_text[1..100]
      else
        short_figure = card_text[1].casecmp('d').zero? ? 'wd4' : 'w'
        short_color = card_text[-1]
        color = if short_color == '4'
                  :wild
                else
                  Jedna.expand_color(short_color)
                end
      end
  
      figure = Jedna.expand_figure(short_figure)
      Card.new(color, figure)
    end
  
    def to_s
      if special_valid_card?
        normalize_figure + normalize_color
      else
        normalize_color + normalize_figure
      end
    end
  
  
    def set_wild_color(color)
      @color = color if special_valid_card?
    end
  
    def unset_wild_color
      @color = :wild if special_valid_card?
    end
  
  
    def normalize_color
      if Jedna::COLORS.member? @color
        Jedna::SHORT_COLORS[Jedna::COLORS.find_index @color]
      else
        throw 'not a valid color'
      end
    end
  
    def self.normalize_color(color)
      if Jedna::COLORS.member? color
        Jedna::SHORT_COLORS[Jedna::COLORS.find_index color]
      else
        throw 'not a valid color'
      end
    end
  
    def normalize_figure
      if Jedna::FIGURES.member? @figure
        Jedna::SHORT_FIGURES[Jedna::FIGURES.find_index @figure]
      end
    end
  
    def self.normalize_figure(figure)
      if Jedna::FIGURES.member? figure
        Jedna::SHORT_FIGURES[Jedna::FIGURES.find_index figure]
      end
    end
  
    def valid_color?
      Jedna::COLORS.member? @color
    end
  
    def self.valid_color?(color)
      Jedna::COLORS.member? color
      end
  
    def valid_figure?
      Jedna::FIGURES.member? @figure
    end
  
    def self.valid_figure?(figure)
      Jedna::FIGURES.member? figure
    end
  
    def special_card?
      Jedna::SPECIAL_FIGURES.member?(@figure)
    end
  
    def special_valid_card?
      Jedna::COLORS.member?(@color) && special_card?
    end
  
    def valid?
      Jedna::COLORS.member?(@color) && Jedna::FIGURES.member?(@figure)
    end
  
    def is_offensive?
      ['+2', 'wild+4'].member? @figure
    end
  
    def offensive_value
      if @figure == '+2'
        2
      elsif @figure == 'wild+4'
        4
      else
        0
      end
    end
  
    def is_war_playable?
      ['+2', 'reverse', 'wild+4'].member? @figure
    end
  
    def plays_after?(card)
      (@color == :wild) || (card.color == :wild) || card.figure == @figure || card.color == @color || special_valid_card?
    end
  
    def is_regular?
      figure.is_a? Integer
    end
  
    def value
      return 50 if special_valid_card?
      return @figure if figure.is_a? Integer
      20
    end
  
    def playability_value
      return -10 if @figure == 'wild+4'
      return -5 if special_valid_card?
      return -3 if is_offensive?
      return -2 if is_war_playable?
      return @figure if figure.is_a? Integer
      0 # if skip
    end
    end
end
