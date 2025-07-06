# frozen_string_literal: true

require_relative "jedna/version"

# Core game files
require_relative "jedna/core/misc"
require_relative "jedna/core/card"
require_relative "jedna/core/hand"
require_relative "jedna/core/card_stack"
require_relative "jedna/core/deck"
require_relative "jedna/core/player"
require_relative "jedna/core/game"

# Interfaces
require_relative "jedna/interfaces/player_identity"
require_relative "jedna/interfaces/notifier"
require_relative "jedna/interfaces/renderer"
require_relative "jedna/interfaces/repository"

# Thread safety (optional)
require_relative "jedna/thread_safe_game"

# Game state serialization
require_relative "jedna/game_state_serializer"

module Jedna
  class Error < StandardError; end
end