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

#### Draw Two War (+2 War)
- **Triggered by**: Someone plays a +2 card
- **Playable cards**: Only +2, Reverse, or Wild Draw 4
- **Effect**: Draw penalty accumulates (2, 4, 6, 8...)
- **Resolution**: When a player can't continue, they draw all accumulated cards

#### Wild Draw Four War (WD4 War)
- **Triggered by**: Someone plays a Wild Draw 4
- **Playable cards**: Only Wild Draw 4
- **Effect**: Draw penalty accumulates (4, 8, 12...)
- **Resolution**: When a player can't continue, they draw all accumulated cards

## Card Types and Effects

### Number Cards (0-9)
- No special effect
- Playable based on color or number match

### Action Cards
- **Skip (S)**: Next player loses their turn
- **Reverse (R)**: Reverses play direction (always reverses, even in 2-player games)
- **Draw Two (+2)**: Next player must respond with +2/Reverse/WD4 or draw accumulated cards

### Wild Cards
- **Wild (W)**: Choose any color for next play
- **Wild Draw Four (WD4)**: Choose color, next player must respond with WD4 or draw accumulated cards

## Special Play Mechanics

### Double Play
- Two identical cards (same color AND figure) can be played simultaneously
- Notation: "r5r5" for two Red 5s
- Works for all cards except Wild Draw 4 (including number cards, +2, Skip, and Reverse)
- Cannot double play a picked card

### Passing
- Pass command (`pa`) only available:
  - After picking a card in normal state
  - In war states when you cannot respond (draws accumulated penalty)
- If you cannot play in normal state, you must pick (`pe`) first

### Picked Card Rule
- If you pick a card and it's playable, you must play that specific card
- Exception: Wild Draw 4 can be played instead of the picked card

## Turn Order
- Clockwise by default
- Reverse cards change direction for all players
- Skip cards bypass next player
- Double Skip bypasses two players

## Winning Conditions
1. First player to play all their cards wins
2. "UNO!" is automatically announced when a player reaches one card
3. Game ends immediately when a player plays their last card

## Scoring (if used)
Points are awarded based on cards left in opponents' hands:
- Number cards: Face value (0-9)
- Action cards: 20 points each
- Wild cards: 50 points each
- Minimum 30 points per game
