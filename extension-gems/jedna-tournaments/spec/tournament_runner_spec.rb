# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'yaml'
require_relative '../examples/tournament_runner'

RSpec.describe ConfiguredTournamentRunner do
  it 'runs every configured game and alternates the first player' do
    examples = File.expand_path('../examples', __dir__)
    config = {
      'agents' => {
        'Simple' => File.join(examples, 'simple_agent.rb'),
        'Crushing' => File.join(examples, 'crushing_agent.rb')
      },
      'games_per_round' => 4,
      'timeouts' => { 'turn_timeout' => 2.0, 'game_timeout' => 15.0 },
      'output' => { 'stdout' => false }
    }

    Tempfile.create(['arena', '.yaml']) do |file|
      file.write(YAML.dump(config))
      file.flush

      results = described_class.new(file.path).run

      expect(results.values.sum).to eq(4)
    end
  end

  it 'propagates engine errors instead of silently omitting a game' do
    config = { 'agents' => { 'A' => 'a', 'B' => 'b' }, 'output' => { 'stdout' => false } }
    arena = instance_double(ArenaGame)
    allow(ArenaGame).to receive(:new).and_return(arena)
    allow(arena).to receive(:play).and_raise('engine defect')

    Tempfile.create(['arena', '.yaml']) do |file|
      file.write(YAML.dump(config))
      file.flush
      runner = described_class.new(file.path)

      expect { runner.run }.to raise_error(RuntimeError, 'engine defect')
      expect(runner.results.values.sum).to eq(0)
      expect(runner.outcomes).to be_empty
    end
  end
end
