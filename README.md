# Jedna!

An extensible Ruby engine for an UNO-inspired card game with custom stacking,
double-play, and instant-loss rules. See [game_rules.md](game_rules.md) for the
implemented rules.

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
  1, # casual mode
  Jedna::ConsoleNotifier.new,
  Jedna::TextRenderer.new,
  Jedna::NullRepository.new
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
if playable_card
  # Wild cards must have a color before they are played through the core API.
  playable_card.set_wild_color(:red) if playable_card.wild?
  game.player_card_play(current_player, playable_card)
end
```

`Game.new` currently uses positional arguments:
`creator, casual, notifier, renderer, repository`. The casual flag is the
integer `1` for casual mode and `0` for persistent mode.

## Interfaces

Jedna! provides several interfaces to customize game behavior:

### Notifier

Handles game messages and notifications:

- `ConsoleNotifier` - Outputs to console
- `NullNotifier` - Captures messages (useful for testing)
- `IrcNotifier` - Sends messages through an IRC adapter; load it with
  `require 'jedna/interfaces/irc_notifier'`

### Renderer

Formats cards and game state:

- `TextRenderer` - Plain text output
- `IrcRenderer` - IRC color codes
- `HtmlRenderer` - HTML formatting for trusted values; it does not escape HTML

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
