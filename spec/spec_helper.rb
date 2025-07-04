# frozen_string_literal: true

require "jedna"
require "tempfile"

# Mock notifier that captures notifications
class TestNotifier
  include Jedna::Notifier
  
  attr_reader :game_notifications, :player_notifications, :errors, :debug_messages
  
  def initialize
    @game_notifications = []
    @player_notifications = []
    @errors = []
    @debug_messages = []
  end
  
  def notify_game(message)
    @game_notifications << message
  end
  
  def notify_player(player_id, message)
    @player_notifications << { player: player_id, text: message }
  end
  
  def notify_error(player_id, error)
    @errors << { player: player_id, error: error }
  end
  
  def debug(message)
    @debug_messages << message
  end
end

# Test game that captures notifications
class TestJednaGame < Jedna::Game
  attr_reader :test_notifier
  
  def initialize(creator, casual = 0)
    @test_notifier = TestNotifier.new
    renderer = Jedna::TextRenderer.new
    repository = Jedna::NullRepository.new
    super(creator, casual, @test_notifier, renderer, repository)
  end
  
  def notifications
    @test_notifier.game_notifications
  end
  
  def player_notifications
    @test_notifier.player_notifications
  end
  
  def clean_up_end_game
    # No-op for tests
  end
end

# Helper to create a game with players
def create_game_with_players(player_names = ['Alice', 'Bob'])
  game = TestJednaGame.new(player_names.first, 1) # casual mode to skip DB
  player_names.each do |name|
    game.add_player(Jedna::Player.new(name))
  end
  game
end

# Helper to start a game and deal cards
def start_game(game)
  game.start_game
  game
end

# RSpec configuration for Jedna tests
module JednaTestHelper
  def self.original_stdout
    @original_stdout ||= $stdout
  end
  
  def self.original_stdout=(value)
    @original_stdout = value
  end
end

RSpec.configure do |config|
  config.before(:suite) do
    # Silence stdout during tests
    JednaTestHelper.original_stdout = $stdout
    $stdout = StringIO.new
  end
  
  config.after(:suite) do
    $stdout = JednaTestHelper.original_stdout
  end
end

# Shared contexts
RSpec.shared_context "jedna game setup" do
  let(:game) { TestJednaGame.new('TestCreator', 1) }
  let(:alice) { Jedna::Player.new('Alice') }
  let(:bob) { Jedna::Player.new('Bob') }
  
  before do
    game.add_player(alice)
    game.add_player(bob)
  end
end

RSpec.shared_context "jedna game started" do
  include_context "jedna game setup"
  
  before do
    game.start_game
  end
end

# Matchers for Jedna tests
RSpec::Matchers.define :be_playable_after do |card|
  match do |actual|
    actual.plays_after?(card)
  end
  
  failure_message do |actual|
    "expected #{actual} to be playable after #{card}"
  end
end

RSpec::Matchers.define :have_notification do |expected|
  match do |game|
    game.notifications.include?(expected)
  end
  
  failure_message do |game|
    "expected game to have notification '#{expected}', but got: #{game.notifications}"
  end
end