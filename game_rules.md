# Rules of IRC Uno

## Objective
Be the first player to play all cards from your hand.

## Basic Playability Rules

### Normal State
A card can be played if it matches the top card by:
1. **Same Color** - e.g., Red 5 → Red 9
2. **Same Number/Figure** - e.g., Red 5 → Blue 5
3. **Wild Cards** - Can always be played (Wild, Wild Draw 4)

### War States
Special states that restrict what can be played:

War restrictions apply **in addition to** normal playability. A non-Wild card
must still match the current top card's color or figure. A Reverse becomes the
new top card without ending the war or clearing the accumulated penalty.

#### Draw Two War (+2 War)
- **Triggered by**: Someone plays a +2 card
- **Playable cards**: A +2 or Reverse that matches the top card by color or
  figure, or a Wild Draw Four
- **Effect**: Draw penalty accumulates (2, 4, 6, 8...)
- **Resolution**: When a player can't continue, they draw all accumulated cards

#### Wild Draw Four War (WD4 War)
- **Triggered by**: Someone plays a Wild Draw 4
- **Playable cards**: A Wild Draw Four, or a Reverse that matches the top card
  by color or figure
- **Effect**: Draw penalty accumulates (4, 8, 12...)
- **Resolution**: When a player can't continue, they draw all accumulated cards

Examples: `r+2 → b+2` is legal because the figures match. After `r+2 → rr`,
`b+2` is illegal (neither color nor figure matches), while `br` is legal
(Reverse matches Reverse). The same Reverse-to-Reverse matching applies in a
WD4 war. A player may also choose to accept the penalty instead of responding.

## Card Types and Effects

### Number Cards (0-9)
- No special effect
- Playable based on color or number match

### Action Cards
- **Skip (S)**: Next player loses their turn
- **Reverse (R)**: Reverses play direction. By default this also applies in a
  2-player game; applications can enable `two_player_reverse_acts_as_skip` so
  that playing Reverse immediately gives the same player another turn.
- **Draw Two (+2)**: Next player must respond with a legal +2/Reverse/WD4 or draw accumulated cards

### Wild Cards
- **Wild (W)**: Choose any color for next play
- **Wild Draw Four (WD4)**: Choose color; the next player must respond with WD4
  or a legal Reverse, or draw accumulated cards

## Special Play Mechanics

### Double Play
- Two identical cards (same color AND figure) can be played simultaneously
- Core API: pass `true` as the third argument to
  `player_card_play(player, card, true)`
- Automated-play protocol: set `"double_play": true` on a play response
- Cannot double play a picked card
- A double Reverse normally preserves player order and gives the same player
  another turn, including with two players. If `two_player_reverse_acts_as_skip`
  is enabled in a two-player game, a single Reverse keeps the turn, while a
  double Reverse passes it to the opponent.

### Passing
- Passing is only available:
  - After picking a card in normal state
  - In war states when accepting the accumulated draw penalty
- If you cannot play in normal state, you must draw first

### Picked Card Rule
- After drawing, you may play the drawn card if it is playable, or pass.
  You cannot play a different card from your hand, even an identical copy.

## Turn Order
- Clockwise by default
- Reverse cards change direction for all players
- A double Reverse preserves direction and normally retains the turn, as
  described under Double Play
- With `two_player_reverse_acts_as_skip` enabled, Reverse skips the opponent in
  a 2-player game
- Skip cards bypass next player
- Double Skip bypasses two players

## Winning Conditions
1. First player to play all their cards wins
2. "UNO!" is automatically announced when a player reaches one card
3. Game ends immediately when a player plays their last card
4. A player loses instantly if drawing takes their hand above 35 cards

## Scoring (if used)
Points are awarded based on cards left in opponents' hands:
- Number cards: Face value (0-9)
- Action cards: 20 points each
- Wild cards: 50 points each
- Minimum 30 points per game
