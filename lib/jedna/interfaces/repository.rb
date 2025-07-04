module Jedna
  # Interface for data persistence operations
  # Implementations handle how game data is stored and retrieved
  module Repository
    # Create a new game record
    def create_game(creator, start_time)
      raise NotImplementedError, "#{self.class} must implement create_game"
    end
    
    # Update game after it ends
    def update_game_ended(game_id, winner, end_time, points, total_players, game_number)
      raise NotImplementedError, "#{self.class} must implement update_game_ended"
    end
    
    # Save a card played or received
    def save_card_action(game_id, card, player, received = false)
      raise NotImplementedError, "#{self.class} must implement save_card_action"
    end
    
    # Record player joining game
    def record_player_join(game_id, player)
      raise NotImplementedError, "#{self.class} must implement record_player_join"
    end
    
    # Record game stopped by player
    def record_game_stopped(game_id, player)
      raise NotImplementedError, "#{self.class} must implement record_game_stopped"
    end
    
    # Get player statistics
    def get_player_stats(player_nick)
      raise NotImplementedError, "#{self.class} must implement get_player_stats"
    end
    
    # Update player statistics after game
    def update_player_stats(player_nick, won, points = 0)
      raise NotImplementedError, "#{self.class} must implement update_player_stats"
    end
  end
  
  # Null repository for testing or casual games
  class NullRepository
    include Repository
    
    def create_game(creator, start_time)
      # Return a mock game ID
      rand(1000)
    end
    
    def update_game_ended(game_id, winner, end_time, points, total_players, game_number)
      # No-op
    end
    
    def save_card_action(game_id, card, player, received = false)
      # No-op
    end
    
    def record_player_join(game_id, player)
      # No-op
    end
    
    def record_game_stopped(game_id, player)
      # No-op
    end
    
    def get_player_stats(player_nick)
      # Return default stats
      {
        nick: player_nick,
        games: 0,
        wins: 0,
        total_score: 0
      }
    end
    
    def update_player_stats(player_nick, won, points = 0)
      # No-op
    end
  end
  
  # SQLite repository using Sequel models
  class SqliteRepository
    include Repository
    
    def initialize(models = {})
      # Models should be injected from the main app
      @game_model = models[:game_model]
      @turn_model = models[:turn_model]
      @action_model = models[:action_model]
      @rank_model = models[:rank_model]
      
      unless @game_model && @turn_model && @action_model && @rank_model
        raise ArgumentError, "All models must be provided: :game_model, :turn_model, :action_model, :rank_model"
      end
    end
    
    def create_game(creator, start_time)
      game = @game_model.create(
        start: start_time,
        created_by: creator
      )
      game.save
      game.ID
    end
    
    def update_game_ended(game_id, winner, end_time, points, total_players, game_number)
      game = @game_model[game_id]
      return unless game
      
      game.points = points
      game.winner = winner
      game.end = end_time
      game.players = total_players
      game.game = game_number
      game.save
    end
    
    def save_card_action(game_id, card, player, received = false)
      dbcard = @turn_model.create(
        card: card.to_s,
        figure: card.normalize_figure,
        color: card.normalize_color,
        player: player.to_s,
        received: received ? 1 : 0,
        time: Time.now.strftime('%F %T'),
        game: game_id
      )
      dbcard.save
    end
    
    def record_player_join(game_id, player)
      action = @action_model.create(
        game: game_id,
        action: 0,  # 0 = join
        player: player,
        subject: player
      )
      action.save
    end
    
    def record_game_stopped(game_id, player)
      action = @action_model.create(
        game: game_id,
        action: 2,  # 2 = stop
        player: player,
        subject: player
      )
      action.save
    end
    
    def get_player_stats(player_nick)
      player_record = @rank_model[player_nick]
      
      if player_record
        {
          nick: player_nick,
          games: player_record.games,
          wins: player_record.wins,
          total_score: player_record.total_score
        }
      else
        {
          nick: player_nick,
          games: 0,
          wins: 0,
          total_score: 0
        }
      end
    end
    
    def update_player_stats(player_nick, won, points = 0)
      player_record = @rank_model[player_nick]
      
      if player_record.nil?
        player_record = @rank_model.create(nick: player_nick)
      end
      
      player_record.games += 1
      if won
        player_record.wins += 1
        player_record.total_score += points
      end
      
      player_record.save
      
      # Return updated stats
      {
        games: player_record.games,
        wins: player_record.wins,
        total_score: player_record.total_score
      }
    end
  end
end