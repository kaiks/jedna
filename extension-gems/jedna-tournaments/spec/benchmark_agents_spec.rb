# frozen_string_literal: true

require 'spec_helper'
require_relative '../examples/benchmark_agents'

RSpec.describe InProcessAgentBenchmark do
  it 'runs complete games and accounts for every winner' do
    wins, = described_class.new('crushing', 'simple', games: 10, seed: 100).run

    expect(wins.values.sum).to eq(10)
  end
end
