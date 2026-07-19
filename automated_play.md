# Automated Play Interface

This document describes the interface for creating automated agents (bots) that can play Jedna.

## Overview

Jedna supports automated agents through a simple JSON-based protocol. Agents can be written in any programming language that can:

1. Read JSON from standard input (stdin)
2. Write JSON to standard output (stdout)
3. Make game decisions based on the current state

## Communication Protocol

### Game State Request (Game → Agent)

When it's an agent's turn, the game sends a JSON object describing the current game state:

```json
{
  "type": "request_action",
  "protocol_version": 1,
  "state": {
    "your_id": "player1",
    "hand": ["r2", "b5", "wd4", "g7", "y1"],
    "top_card": "r7",
    "game_state": "normal",
    "stacked_cards": 0,
    "already_picked": false,
    "picked_card": null,
    "other_players": [
      {"id": "player2", "card_count": 3},
      {"id": "player3", "card_count": 7}
    ],
    "available_actions": ["play", "draw"],
    "playable_cards": ["r2"]
  }
}
```

#### State Fields

- `type`: Always "request_action" for action requests
- `protocol_version`: Integer version of the request envelope and canonical
  state contract. The current version is `1`.
- `state`: Object containing the game state
  - `your_id`: The agent's player ID
  - `hand`: Array of card codes in the agent's hand
  - `top_card`: The current top card on the discard pile
  - `game_state`: Current game state ("normal", "war_+2", "war_wd4")
  - `stacked_cards`: Number of cards stacked in war (must draw if passing)
  - `already_picked`: Whether a card was already drawn this turn
  - `picked_card`: The card drawn this turn (if any)
  - `other_players`: Array of other players with their card counts, ordered from
    next to act through the player reached by reversing direction
  - `available_actions`: Action categories exposed in the current state.
  - `playable_cards`: List of cards from hand that can be played now

### Agent Response (Agent → Game)

The agent must respond with a JSON object specifying the action:

#### Play a Card

```json
{
  "action": "play",
  "card": "r2",
  "wild_color": "blue",
  "double_play": true
}
```
- `card`: The card code to play (must be from hand)
- `wild_color`: Required only when playing wild cards ("red", "blue", "green", "yellow")
- `double_play` (optional): Requests that an identical second card be played in
  the same turn. The flag must be supplied on the original play.

#### Draw a Card

```json
{
  "action": "draw"
}
```

#### Pass Turn

```json
{
  "action": "pass"
}
```
Note: Pass is only valid after drawing or when forced to draw stacked cards.

### Game Notifications (Game → Agent)

The game also sends informational messages about game events:

```json
{
  "type": "notification",
  "message": "player2 played b5"
}
```

```json
{
  "type": "error",
  "message": "Invalid card: that card is not in your hand"
}
```

```json
{
  "type": "game_end",
  "winner": "player3",
  "scores": {
    "player1": 15,
    "player2": 23,
    "player3": 0
  }
}
```

## Card Notation

Cards are represented as strings:

### Number Cards

- Format: `[color][number]`
- Examples: `r5` (red 5), `b0` (blue 0), `y9` (yellow 9)

### Action Cards

- Skip: `[color]s` - e.g., `rs` (red skip)
- Reverse: `[color]r` - e.g., `br` (blue reverse)
- Draw Two: `[color]+2` - e.g., `g+2` (green draw two)

### Wild Cards

- Wild: `w` (wild)
- Wild Draw Four: `wd4` (wild draw four)

Colors: `r` (red), `b` (blue), `g` (green), `y` (yellow)

## Game Rules Summary

### War States

- **+2 War**: The next player may respond with another +2, a Wild Draw Four,
  or a reverse matching the current color; otherwise they draw the accumulated
  cards.
- **WD4 War**: The next player may respond with another Wild Draw Four or a
  reverse matching the selected color; otherwise they draw the accumulated
  cards.
- Wars stack: multiple +2 or wd4 cards accumulate the penalty

### Special Rules

- **Picked Card Rule**: If you draw a card and it's playable, you may play it same turn
- **Pass Rule**: You can only pass after drawing a card (or being forced to draw)

## Example Agent Implementation

### Ruby Example

```ruby
#!/usr/bin/env ruby
require 'json'

class SimpleAgent
  def run
    loop do
      input = gets
      break if input.nil?
      
      data = JSON.parse(input)
      
      case data['type']
      when 'request_action'
        action = decide_action(data['state'])
        puts JSON.generate(action)
        STDOUT.flush
      when 'game_end'
        break
      end
    end
  end
  
  private
  
  def decide_action(state)
    # Simple strategy: play first playable card, otherwise draw
    if state['playable_cards'].any?
      card = state['playable_cards'].first
      action = { 'action' => 'play', 'card' => card }
      
      # Add color for wild cards
      if card == 'w' || card == 'wd4'
        # Pick the color we have most of
        colors = state['hand'].map { |c| c[0] }.reject { |c| c == 'w' }
        color_counts = colors.tally
        best_color = color_counts.max_by { |_, count| count }&.first || 'r'
        action['wild_color'] = color_name(best_color)
      end
      
      action
    elsif state['available_actions'].include?('draw')
      { 'action' => 'draw' }
    else
      { 'action' => 'pass' }
    end
  end
  
  def color_name(letter)
    { 'r' => 'red', 'b' => 'blue', 'g' => 'green', 'y' => 'yellow' }[letter]
  end
end

SimpleAgent.new.run if __FILE__ == $0
```

### Python Example

```python
#!/usr/bin/env python3
import json
import sys
from collections import Counter

class SimpleAgent:
    def run(self):
        while True:
            try:
                line = input()
                data = json.loads(line)
                
                if data['type'] == 'request_action':
                    action = self.decide_action(data['state'])
                    print(json.dumps(action))
                    sys.stdout.flush()
                elif data['type'] == 'game_end':
                    break
                    
            except EOFError:
                break
    
    def decide_action(self, state):
        # Simple strategy: play first playable card, otherwise draw
        if state['playable_cards']:
            card = state['playable_cards'][0]
            action = {'action': 'play', 'card': card}
            
            # Add color for wild cards
            if card in ('w', 'wd4'):
                # Pick the color we have most of
                colors = [c[0] for c in state['hand'] if c[0] != 'w']
                if colors:
                    color_counts = Counter(colors)
                    best_color = color_counts.most_common(1)[0][0]
                else:
                    best_color = 'r'
                
                color_map = {'r': 'red', 'b': 'blue', 'g': 'green', 'y': 'yellow'}
                action['wild_color'] = color_map[best_color]
            
            return action
        elif 'draw' in state['available_actions']:
            return {'action': 'draw'}
        else:
            return {'action': 'pass'}

if __name__ == '__main__':
    SimpleAgent().run()
```

## Testing Your Agent

To test your agent locally with Jedna, you'll need the `jedna-tournaments` gem (see extension-gems/jedna-tournaments).

Basic testing approach:

1. Run your agent as a subprocess
2. Send it game states via stdin
3. Read its responses from stdout
4. Validate the responses match the expected format

Canonical request fixtures are available in `spec/fixtures/protocol`. They
cover a normal turn, a post-draw decision, and both war states. Integrations
should use these fixtures for contract tests instead of duplicating sample
payloads.

## Embedding Automated Play

Ruby hosts can apply one response with `Jedna::ActionExecutor`:

```ruby
executor = Jedna::ActionExecutor.new(game)
result = executor.execute(action, player: game.players.first)

unless result.success?
  warn "#{result.code}: #{result.message}"
end
```

The executor accepts string- or symbol-keyed action hashes. It validates the
current player, action availability, card, wild color, and double play before
calling the game API. It returns an immutable `Jedna::ActionResult` with
`success?`, `error?`, `code`, `message`, and `action`; expected protocol errors
are results rather than exceptions. When the game includes `ThreadSafeGame`,
validation and application run together inside the game's reentrant monitor.

Games also expose `on_action_required` for event-driven hosts:

```ruby
game.on_action_required do |current_game, current_player, reason|
  queue << [current_game, current_player, reason]
end
```

`reason` is `:turn_started` at the beginning of each turn and `:card_drawn`
after a successful single-card draw. The latter event is the second decision
point where the player must play the drawn card or pass. Hooks execute inline;
thread-safe hosts should enqueue a snapshot and return immediately rather than
performing agent I/O while the game monitor is held.

## Performance Considerations

- Agents should respond within 5 seconds (configurable in tournaments)
- Agents that timeout or crash forfeit the game
- Agents should not output anything except valid JSON responses
- Debug output should go to stderr, not stdout

## Advanced Strategies

Successful agents typically consider:
- Card counting (tracking played cards)
- Opponent modeling (card count patterns)
- Strategic +2/wd4 timing
- Color control for endgame
- Risk assessment for wd4 challenges

## Protocol Versioning

Current protocol version: 1

Future versions will maintain backwards compatibility or provide migration guides.
