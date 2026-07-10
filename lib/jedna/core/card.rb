# frozen_string_literal: true

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
    raise ArgumentError, "not a valid color: #{short_color}" unless SHORT_COLORS.member? short_color

    COLORS[SHORT_COLORS.find_index short_color]
  end

  def self.expand_figure(short_figure)
    short_figure = short_figure.downcase
    return FIGURES[SHORT_FIGURES.find_index short_figure] if SHORT_FIGURES.member? short_figure

    return 'wild' if short_figure == '*'

    raise ArgumentError, "not a valid figure: #{short_figure}"
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
      raise ArgumentError, 'Wrong color' unless Jedna::COLORS.include? color
      raise ArgumentError, 'Wrong figure' unless Jedna::FIGURES.include? figure

      @color = color
      @figure = figure
      @visited = 0
      @debug = false

      raise ArgumentError, "Not a valid card #{@color} #{@figure}" unless valid?
    end

    def <=>(other)
      return nil unless other.is_a?(Card)

      [@figure.to_s, @color.to_s] <=> [other.figure.to_s, other.color.to_s]
    end

    def ==(other)
      return false unless other.is_a?(Card)

      (@figure.to_s == other.figure.to_s) && (@color == other.color)
    end

    def self.parse(card_text)
      card_text = card_text.downcase

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
      return Card.new(:wild, 'wild') if %w[w ww].include?(card_text)

      wild_match = /\Aw([rgby])\z/.match(card_text)
      return Card.new(Jedna.expand_color(wild_match[1]), 'wild') if wild_match

      draw_four_match = /\Awd4([rgby])?\z/.match(card_text)
      if draw_four_match
        color = draw_four_match[1] ? Jedna.expand_color(draw_four_match[1]) : :wild
        return Card.new(color, 'wild+4')
      end

      raise ArgumentError, "not a valid wild card: #{card_text}"
    end

    def to_s
      if special_valid_card?
        normalize_figure + normalize_color
      else
        normalize_color + normalize_figure
      end
    end

    def set_wild_color(color)
      return self unless special_card?

      color = color.downcase.to_sym if color.is_a?(String)
      raise ArgumentError, "not a valid wild color: #{color}" unless Jedna::COLORS.first(4).include?(color)

      @color = color
      self
    end

    def unset_wild_color
      @color = :wild if special_card?
      self
    end

    def normalize_color
      raise ArgumentError, 'not a valid color' unless Jedna::COLORS.member? @color

      Jedna::SHORT_COLORS[Jedna::COLORS.find_index @color]
    end

    def self.normalize_color(color)
      raise ArgumentError, 'not a valid color' unless Jedna::COLORS.member? color

      Jedna::SHORT_COLORS[Jedna::COLORS.find_index color]
    end

    def normalize_figure
      return unless Jedna::FIGURES.member? @figure

      Jedna::SHORT_FIGURES[Jedna::FIGURES.find_index @figure]
    end

    def self.normalize_figure(figure)
      return unless Jedna::FIGURES.member? figure

      Jedna::SHORT_FIGURES[Jedna::FIGURES.find_index figure]
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

    def wild?
      special_card?
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
