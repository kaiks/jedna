# frozen_string_literal: true

require 'spec_helper'
require_relative '../examples/tournament_runner'

RSpec.describe ArenaGame, 'failure handling' do
  let(:alice) do
    instance_double(JednaTournaments::ProcessAgent, start: nil, stop: nil, notify_game_end: nil)
  end
  let(:bob) do
    instance_double(JednaTournaments::ProcessAgent, start: nil, stop: nil, notify_game_end: nil)
  end
  let(:arena) { described_class.new({ 'Alice' => 'alice', 'Bob' => 'bob' }, turn_timeout: 1, game_timeout: 5) }

  before do
    allow(JednaTournaments::ProcessAgent).to receive(:new).with('alice', 'Alice').and_return(alice)
    allow(JednaTournaments::ProcessAgent).to receive(:new).with('bob', 'Bob').and_return(bob)
  end

  it 'awards a forfeit on timeout and releases both agents' do
    allow(alice).to receive(:request_action).and_raise(JednaTournaments::TimeoutError, 'too slow')

    expect(arena.play).to eq('Bob')
    expect(arena.outcome).to include(winner: 'Bob', loser: 'Alice', reason: :timeout)
    expect(alice).to have_received(:stop)
    expect(bob).to have_received(:stop)
    expect(bob).to have_received(:notify_game_end).with('Bob', {})
  end

  it 'forfeits a startup failure and cleans up agents already started' do
    allow(bob).to receive(:start).and_raise(JednaTournaments::AgentError, 'cannot start')

    expect(arena.play).to eq('Alice')
    expect(arena.outcome).to include(loser: 'Bob', reason: :agent_error)
    expect(alice).to have_received(:stop)
  end

  it 'forfeits an invalid protocol object' do
    allow(alice).to receive(:request_action).and_return(['play'])

    expect(arena.play).to eq('Bob')
    expect(arena.outcome).to include(reason: :invalid_action)
  end

  it 'forfeits an unavailable action without substituting a draw' do
    allow(alice).to receive(:request_action).and_return('action' => 'pass')

    expect(arena.play).to eq('Bob')
    expect(arena.outcome).to include(reason: :invalid_action, message: 'pass is not available')
  end

  it 'forfeits an agent failure during the post-draw decision' do
    calls = 0
    allow(alice).to receive(:request_action) do
      calls += 1
      raise JednaTournaments::AgentError, 'closed output' if calls == 2

      { 'action' => 'draw' }
    end

    expect(arena.play).to eq('Bob')
    expect(arena.outcome).to include(reason: :agent_error)
    expect(calls).to eq(2)
  end

  it 'propagates engine defects without declaring a winner' do
    executor = instance_double(Jedna::ActionExecutor)
    allow(Jedna::ActionExecutor).to receive(:new).and_return(executor)
    allow(executor).to receive(:execute).and_raise('engine defect')
    allow(alice).to receive(:request_action).and_return('action' => 'draw')

    expect { arena.play }.to raise_error(RuntimeError, 'engine defect')
    expect(arena.outcome).to be_nil
    expect(alice).to have_received(:stop)
    expect(bob).to have_received(:stop)
  end
end
