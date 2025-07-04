# Jedna!

A flexible, extensible card game engine that implements the rules of UNO!.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'jedna'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install jedna

## Usage

```ruby
require 'jedna'

# Create a game with console output
game = Jedna::Game.new(
  'Creator',
  casual: false,
  notifier: Jedna::ConsoleNotifier.new,
  renderer: Jedna::TextRenderer.new
)

# Add players
alice = Jedna::Player.new('Alice')
bob = Jedna::Player.new('Bob')

game.add_player(alice)
game.add_player(bob)

# Start the game
game.start_game

# Play cards
current_player = game.players[0]
playable_card = current_player.hand.find { |card| game.playable_now?(card) }
game.player_card_play(current_player, playable_card) if playable_card
```

## Interfaces

Jedna! provides several interfaces to customize game behavior:

### Notifier
Handles game messages and notifications:
- `ConsoleNotifier` - Outputs to console
- `NullNotifier` - Captures messages (useful for testing)

### Renderer
Formats cards and game state:
- `TextRenderer` - Plain text output
- `IrcRenderer` - IRC color codes
- `HtmlRenderer` - HTML formatting

### Repository
Handles game persistence:
- `SqliteRepository` - SQLite database storage
- `NullRepository` - No persistence (casual games)

### PlayerIdentity
Manages player identification:
- `SimpleIdentity` - Basic string-based identity
- `IrcIdentity` - IRC nick-based identity
- `UuidIdentity` - UUID-based identity

## License

This software is licensed under the PolyForm Noncommercial License 1.0.0. See the LICENSE file for details.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kaiks/jedna.
