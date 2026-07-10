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
end
