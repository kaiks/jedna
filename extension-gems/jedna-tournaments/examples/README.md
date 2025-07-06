# Jedna Tournament Examples

This directory contains example agents and scripts for running Jedna tournaments.

## Agents

### simple_agent.rb / simple_agent.py
Basic agents that demonstrate the minimal implementation needed to play Jedna. They:
- Play the first available card
- Choose wild colors based on the most common color in hand
- Draw when no cards can be played

### smart_agent.rb
A more sophisticated Ruby agent that:
- Considers game state (wars, opponents close to winning)
- Makes strategic decisions about when to play offensive cards
- Tracks played cards for better decision making

## Running Games

### Single Game
Run one game between two agents:

```bash
./run_single_game.rb './simple_agent.rb' 'python3 simple_agent.py'
```

Output shows the game progress and final winner.

### Tournament
Run multiple games to compare agent performance:

```bash
# Run 100 games (default)
./run_tournament.rb './simple_agent.rb' './smart_agent.rb'

# Run specific number of games
./run_tournament.rb './simple_agent.rb' 'python3 simple_agent.py' 50
```

Output shows:
- Win rates for each agent
- Average game length
- Total duration

## Creating Your Own Agent

Agents communicate via JSON over stdin/stdout. See the [Automated Play documentation](../../../automated_play.md) for the full protocol specification.

Key points:
1. Read JSON from stdin
2. Respond with actions when requested
3. Remember to specify colors for wild cards
4. Exit cleanly when receiving game_end message

## Configurable Tournaments

Use `tournament_runner.rb` with a YAML configuration file for advanced tournaments:

```bash
# Run round-robin tournament
./tournament_runner.rb tournament_config.yaml

# Run elimination bracket
./tournament_runner.rb elimination_config.yaml
```

### Configuration Options

```yaml
agents:
  AgentName: 'command to run agent'
  
tournament_type: round-robin  # or 'elimination-bracket'
games_per_round: 10

output:
  stdout: true                    # Show progress
  log_file: full.log             # Log everything (optional)
  log_results_file: results.txt  # Save final results (optional)
```

See `tournament_config.yaml` and `elimination_config.yaml` for examples.

## Testing Your Agent

Before running tournaments, test your agent handles all game situations:

```bash
# Test against simple agent
./run_single_game.rb './your_agent.rb' './simple_agent.rb'

# Run small tournament to check stability
./run_tournament.rb './your_agent.rb' './simple_agent.rb' 10
```