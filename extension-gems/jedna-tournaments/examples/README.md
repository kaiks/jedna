# Jedna Tournament Examples

This directory contains a complete tournament system for evaluating Jedna card game agents, including example agents, tournament runners, and analysis tools.

## Overview

The tournament system allows you to:
- Run round-robin or elimination tournaments between AI agents
- Execute games in parallel for faster results
- Analyze results with statistical confidence intervals
- Test and improve agent strategies

## Quick Start

```bash
# Run a simple tournament with 100 games
ruby tournament_runner.rb tournament_config.yaml

# Run 4000 games in parallel for high confidence results
./run_tournament.sh tournament_4k.yaml

# Analyze results from a completed tournament
ruby analyze_results.rb 570 1000  # 570 wins out of 1000 games
```

## Directory Structure

### Core Agents
- `simple_agent.rb` / `simple_agent.py` - Basic reference agents that play the first available card
- `smart_agent.rb` - Python-ported agent with chain detection and strategic play
- `smarter_agent.rb` - Enhanced Ruby agent with 17 tested strategies (57% win rate)

### Tournament Runners
- `tournament_runner.rb` - Main tournament engine supporting round-robin and elimination formats
- `parallel_tournament_runner.rb` - Basic parallel execution across multiple processes
- `parallel_tournament_advanced.rb` - Advanced parallel runner with progress tracking and graceful shutdown
- `run_tournament.sh` - Convenience script for running tournaments with clean output

### Testing & Analysis
- `test_smarter_agent.rb` - Comprehensive test suite with 17 strategic scenarios
- `analyze_results.rb` - Statistical analysis tool for tournament results
- `sample_size_calculator.rb` - Calculate required games for statistical confidence
- `run_single_game.rb` - Debug tool for running individual games

### Configuration Files
- `tournament_config.yaml` - Example round-robin tournament configuration
- `elimination_config.yaml` - Example elimination bracket configuration  
- `parallel_tournament_config.yaml` - Parallel execution configuration
- `tournament_4k.yaml` - Production config for high-confidence results (4000 games)

### Documentation
- `agent_improvement_strategy.md` - Log of agent development iterations and learnings
- `test_suite_summary.md` - Overview of all agent tests and their purposes

## Running Tournaments

### Basic Tournament

```bash
# Run with default configuration
ruby tournament_runner.rb tournament_config.yaml

# The configuration specifies:
# - Which agents to run
# - Tournament format (round-robin or elimination)
# - Number of games per match
# - Output options
```

### Parallel Tournaments

For large numbers of games, use parallel execution:

```bash
# Run 4000 games across 4 processes
ruby parallel_tournament_runner.rb tournament_4k.yaml

# Or use the advanced runner with progress tracking
ruby parallel_tournament_advanced.rb tournament_4k.yaml
```

The parallel runner will:
1. Split games across multiple processes
2. Show real-time progress and ETA
3. Merge results automatically
4. Calculate confidence intervals

### Statistical Analysis

To understand your results:

```bash
# Calculate sample size needed for desired confidence
ruby sample_size_calculator.rb

# Analyze tournament results
ruby analyze_results.rb <wins> <total_games>
# Example: ruby analyze_results.rb 570 1000
```

## Creating Your Own Agent

Agents communicate via JSON over stdin/stdout. See the [Automated Play documentation](../../../automated_play.md) for the full protocol specification.

### Basic Agent Structure

```ruby
#!/usr/bin/env ruby
require 'json'

loop do
  input = gets
  break if input.nil?
  
  data = JSON.parse(input)
  
  case data['type']
  when 'request_action'
    # Analyze game state and decide action
    action = decide_action(data['state'])
    puts JSON.generate(action)
    STDOUT.flush
  when 'game_end'
    break
  end
end
```

### Key Strategies (from SmartRuby Agent)

1. **Wild Card Conservation** - Don't waste wd4 when other options exist
2. **War Handling** - Use reverse cards to counter +2/wd4 wars
3. **Defensive Play** - Disrupt opponents when they have UNO
4. **Chain Detection** - Identify sequences of playable cards
5. **Skip Chains** - Recognize winning patterns with multiple skip cards

## Testing Your Agent

### Unit Testing

Create a test file like `test_smarter_agent.rb`:

```ruby
def test_defensive_play
  action = simulate_agent_decision(
    hand = ['b2', 'b5', 'wd4'],
    top_card = 'b9',
    playable_cards = ['b2', 'b5', 'wd4'],
    opponent_cards = [1]  # Opponent has UNO!
  )
  
  assert_equal 'wd4', action['card']
end
```

### Integration Testing

```bash
# Test single game
./run_single_game.rb './your_agent.rb' './simple_agent.rb'

# Small tournament for stability
ruby tournament_runner.rb test_config.yaml
```

## Statistical Confidence

For tournament results to be meaningful:

- **100 games**: ±10% margin of error
- **500 games**: ±4.5% margin of error  
- **1000 games**: ±3.2% margin of error
- **4148 games**: ±2% margin of error (99% confidence)

Use `sample_size_calculator.rb` to determine games needed for your desired confidence level.

## Performance Tips

1. **Disable output** for speed: Set `stdout: false` in config
2. **Use parallel execution** for large tournaments
3. **Set appropriate timeouts** to handle stuck agents
4. **Monitor progress** with the advanced parallel runner

## Troubleshooting

- **Agent crashes**: Check the log files in the output directory
- **Timeouts**: Increase `turn_timeout` in configuration
- **Debug output**: The Jedna engine outputs DEBUG messages; redirect stderr to silence
- **Parallel issues**: Reduce process count if system is overloaded