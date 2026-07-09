# Jedna Tournaments

Tournament infrastructure for running automated Jedna card game matches between AI agents.

## Overview

The library currently provides:

- Agent process management (stdin/stdout communication)
- A `BaseAgent` interface
- A configurable per-response timeout

Round-robin, elimination, result reporting, and parallel execution currently
live in the `examples/` scripts. They are not public classes in
`JednaTournaments`.

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

### Running an Agent Process

```ruby
require 'jedna_tournaments'

agent = JednaTournaments::ProcessAgent.new('./examples/simple_agent.rb')
agent.start

state = {
  your_id: 'bot',
  hand: ['r5'],
  top_card: 'r3',
  game_state: 'normal',
  stacked_cards: 0,
  already_picked: false,
  picked_card: nil,
  other_players: [{ id: 'opponent', card_count: 7 }],
  available_actions: %w[play draw],
  playable_cards: ['r5']
}

response = agent.request_action(state)
puts response.inspect
agent.stop
```

### Running a Tournament Example

```bash
cd extension-gems/jedna-tournaments/examples
bundle exec ruby tournament_runner.rb tournament_config.yaml
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

## Example Tournament Formats

### Round Robin
The example runner supports round-robin and single-elimination brackets. Set
`tournament_type` in the YAML configuration to `round-robin` or
`elimination-bracket`.

```yaml
tournament_type: round-robin
games_per_round: 20
```

## Configuration

```ruby
JednaTournaments.configure do |config|
  config.timeout = 5.0 # ProcessAgent response timeout in seconds
end
```

The configuration object also exposes `log_games`, `log_dir`, `parallel`, and
`max_threads`, but the library classes do not consume those settings. The
example runners use their own YAML configuration.

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
   - `running?` - Report whether the agent is available

## Examples

See the `examples/` directory for sample agents in various languages:
- `simple_agent.rb` - Basic Ruby agent
- `simple_agent.py` - Basic Python agent
- `smart_agent.rb` - More sophisticated Ruby agent
- `crushing_agent.rb` - Smart-derived agent with tested two-player tactics
- `benchmark_agents.rb` - Fast seeded benchmark for bundled Ruby agents
- `crushing_agent_results.md` - Reproducible benchmark results and commands
- `run_single_game.rb` - Run and debug one game
- `tournament_runner.rb` - YAML-configured example tournament

`ProcessAgent` executes the supplied command. Treat command strings as trusted
configuration; do not pass untrusted user input into them.

## Contributing

1. Fork the repository
2. Create your feature branch
3. Write tests for your changes
4. Ensure all tests pass
5. Submit a pull request

## License

This gem is available under the same license as Jedna (PolyForm Noncommercial License 1.0.0).
