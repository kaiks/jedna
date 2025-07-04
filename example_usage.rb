#!/usr/bin/env ruby

# Example of how to use the Jedna gem

require_relative 'lib/jedna'

# Example 1: Create a simple console game
game = Jedna::Game.new(
  'Player1', 
  0, 
  Uno::ConsoleNotifier.new,
  Uno::TextRenderer.new,
  Uno::NullRepository.new
)

# Add players
player1 = Jedna::Player.new('Player1')
player2 = Jedna::Player.new('Player2')

game.add_player(player1)
game.add_player(player2)

# Start the game
game.start_game

# Example 2: Using with SQLite repository (requires models to be injected)
# This shows how to integrate with an existing database setup

# class MyGameModel < Sequel::Model(:games)
#   # Your game model implementation
# end
# 
# class MyTurnModel < Sequel::Model(:turn)
#   # Your turn model implementation
# end
# 
# class MyActionModel < Sequel::Model(:player_action)
#   # Your action model implementation
# end
# 
# class MyRankModel < Sequel::Model(:uno)
#   # Your rank model implementation
# end
# 
# # Create repository with injected models
# repository = Uno::SqliteRepository.new(
#   game_model: MyGameModel,
#   turn_model: MyTurnModel,
#   action_model: MyActionModel,
#   rank_model: MyRankModel
# )
# 
# # Create game with database support
# db_game = Jedna::Game.new(
#   'Player1',
#   0,
#   Uno::ConsoleNotifier.new,
#   Uno::TextRenderer.new,
#   repository
# )

# Example 3: Thread-safe game for IRC bot usage
class ThreadSafeUnoGame < Jedna::Game
  include ThreadSafeGame
end

# irc_game = ThreadSafeUnoGame.new(
#   creator_nick,
#   casual_mode,
#   Uno::IrcNotifier.new(bot, channel),
#   Uno::IrcRenderer.new,
#   repository
# )