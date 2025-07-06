# Jedna Tournaments

Tournament infrastructure for running automated Jedna card game matches between AI agents.

## Overview

This gem provides the infrastructure to run tournaments between automated Jedna agents. It handles:
- Agent process management (stdin/stdout communication)
- Game orchestration with multiple agents
- Tournament formats (round-robin, elimination)
- Result tracking and statistics
- Timeout handling and error recovery

## Installation

Add to your Gemfile:

```ruby
gem 'jedna_tournaments', path: 'extension-gems/jedna-tournaments'
```

Or install directly:

```bash
cd extension-gems/jedna-tournaments
bundle install
gem build jedna_tournaments.gemspec
gem install ./jedna_tournaments-0.1.0.gem
```

## Usage

### Running a Simple Match

```ruby
require 'jedna_tournaments'

# Create agents
agent1 = JednaTournaments::ProcessAgent.new('./examples/simple_agent.rb')
agent2 = JednaTournaments::ProcessAgent.new('python3 ./examples/simple_agent.py')

# Run a single match
match = JednaTournaments::Match.new([agent1, agent2])
result = match.play

puts "Winner: #{result.winner}"
puts "Scores: #{result.scores}"
```

### Running a Tournament

```ruby
# Define agents
agents = [
  { name: 'Ruby Bot', command: './examples/simple_agent.rb' },
  { name: 'Python Bot', command: 'python3 ./examples/simple_agent.py' },
  { name: 'Smart Bot', command: './examples/smart_agent.rb' }
]

# Run round-robin tournament
tournament = JednaTournaments::Tournament.new(agents)
results = tournament.run_round_robin(games_per_match: 10)

# Display results
results.display_leaderboard
```

### Creating Custom Agents

Agents communicate via JSON over stdin/stdout. See the [Jedna Automated Play documentation](../../automated_play.md) for the protocol specification.

Example agent structure:

```ruby
#!/usr/bin/env ruby
require 'json'

class MyAgent
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
    # Your agent logic here
  end
end

MyAgent.new.run if __FILE__ == $0
```

## Tournament Formats

### Round Robin
Every agent plays every other agent a fixed number of times.

```ruby
results = tournament.run_round_robin(games_per_match: 20)
```

### Elimination
Single or double elimination brackets.

```ruby
results = tournament.run_elimination(type: :single)
```

### Swiss
Players are paired based on performance.

```ruby
results = tournament.run_swiss(rounds: 7)
```

## Configuration

```ruby
JednaTournaments.configure do |config|
  config.timeout = 5.0          # Agent response timeout in seconds
  config.log_games = true       # Log all game states
  config.log_dir = './logs'     # Directory for game logs
  config.parallel = true        # Run matches in parallel
  config.max_threads = 4        # Max parallel matches
end
```

## Testing Agents

The gem includes utilities for testing agents:

```ruby
# Test an agent with specific game states
tester = JednaTournaments::AgentTester.new('./my_agent.rb')

# Test specific scenario
state = {
  your_id: 'test',
  hand: ['r5', 'b7', 'wd4'],
  top_card: 'r3',
  # ... other state
}

response = tester.test_action(state)
puts "Agent played: #{response['card']}"

# Run test suite
results = tester.run_test_suite
puts "Passed: #{results.passed}/#{results.total}"
```

## Development

### Running Tests

```bash
cd extension-gems/jedna-tournaments
bundle exec rspec
```

### Adding New Agent Types

1. Create a new class inheriting from `JednaTournaments::BaseAgent`
2. Implement the required methods:
   - `start` - Initialize the agent
   - `request_action(state)` - Get agent's action
   - `notify(message)` - Send notification to agent
   - `stop` - Clean up agent resources

## Examples

See the `examples/` directory for sample agents in various languages:
- `simple_agent.rb` - Basic Ruby agent
- `simple_agent.py` - Basic Python agent
- `smart_agent.rb` - More sophisticated Ruby agent
- `test_scenarios.rb` - Test specific game scenarios

## Contributing

1. Fork the repository
2. Create your feature branch
3. Write tests for your changes
4. Ensure all tests pass
5. Submit a pull request

## License

This gem is available under the same license as Jedna (PolyForm Noncommercial License 1.0.0).