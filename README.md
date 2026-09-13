# Jedna!

An extensible Ruby engine for an UNO-inspired card game with custom stacking,
double-play, and instant-loss rules. See [game_rules.md](game_rules.md) for the
implemented rules.

For the current automated-player recommendation, benchmark record, rejected
experiments, and research backlog, see [BOT_RESEARCH.md](BOT_RESEARCH.md).

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

Each `Game` instance represents one match. `finished?` becomes true after a win,
instant loss, or cancellation; `started?` then remains false. Drawing, passing,
playing, and starting the same instance again cannot reopen it. Create a new
`Game` and new `Player` objects for another match.

`stop_game(player_id)` cancels without awarding points; `end_game(player_id)`
is a compatibility entry point for the same operation. Cancellation is
idempotent. Removing players cancels an active game when fewer than two remain;
removing the last player from a waiting game also cancels it. `on_game_ended`
continues to report wins and instant losses, not cancellations.

The direct play API requires the actual `Player` registered in the game and the
actual `Card` object in that player's hand. A freshly parsed copy is not a hand
card. After drawing, only the actual drawn card may be played. An unavailable
double play rejects the entire action. Protocol hosts can use `ActionExecutor`
to resolve card codes and apply these checks.

Private notifications, joins, card actions, winners, and player statistics use
`player.identity.id`; rendered messages use the display name. This is unchanged
for nick-based identities but changes keys for UUID identities. Hosts that
previously stored UUID players under display names must migrate those records
using their own identity mapping before combining old and new statistics.
Display-name collisions cannot be migrated automatically without that mapping.

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
- `HtmlRenderer` - HTML formatting with escaped dynamic values

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
