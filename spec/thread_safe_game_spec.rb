# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ThreadSafeGame do
  let(:game_class) do
    Class.new(Jedna::Game) do
      include ThreadSafeGame

      attr_reader :entered_add_player, :release_add_player

      def initialize(*args)
        @entered_add_player = Queue.new
        @release_add_player = Queue.new
        super
      end

      def add_player(player)
        @entered_add_player << true
        @release_add_player.pop
        super
      end
    end
  end

  it 'serializes inherited game methods' do
    game = game_class.new('creator', 1, Jedna::NullNotifier.new)
    attempting_read = Queue.new
    completed = Queue.new

    adding_player = Thread.new do
      game.add_player(Jedna::Player.new('Alice'))
    end
    game.entered_add_player.pop

    reading_state = Thread.new do
      attempting_read << true
      completed << game.started?
    end
    attempting_read.pop

    expect(reading_state.join(0.05)).to be_nil
    expect { completed.pop(true) }.to raise_error(ThreadError)

    game.release_add_player << true
    adding_player.join
    reading_state.join

    expect(completed.pop).to be(false)
  end
end
