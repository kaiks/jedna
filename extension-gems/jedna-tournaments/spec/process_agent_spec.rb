# frozen_string_literal: true

require 'spec_helper'

RSpec.describe JednaTournaments::ProcessAgent do
  let(:echo_agent_path) { File.expand_path('support/echo_agent.rb', __dir__) }
  let(:agent) { described_class.new(echo_agent_path) }

  after do
    agent.stop if agent.running?
  end

  describe '#initialize' do
    it 'accepts a command string' do
      expect { described_class.new('ruby -e "puts 1"') }.not_to raise_error
    end

    it 'accepts a command with arguments' do
      expect { described_class.new("ruby #{echo_agent_path}") }.not_to raise_error
    end
  end

  describe '#start' do
    it 'starts the agent process' do
      expect(agent.running?).to be false
      agent.start
      expect(agent.running?).to be true
    end

    it 'raises error if already started' do
      agent.start
      expect { agent.start }.to raise_error(JednaTournaments::AgentError, /already running/)
    end
  end

  describe '#stop' do
    it 'stops the agent process' do
      agent.start
      expect(agent.running?).to be true
      agent.stop
      expect(agent.running?).to be false
    end

    it 'does nothing if not running' do
      expect { agent.stop }.not_to raise_error
    end
  end

  describe '#request_action' do
    before { agent.start }

    it 'sends game state and receives action' do
      state = {
        your_id: 'test',
        hand: %w[r5 b7],
        top_card: 'r3',
        game_state: 'normal',
        available_actions: %w[play draw]
      }

      response = agent.request_action(state)
      expect(response).to eq({ 'action' => 'draw' })
    end

    it 'raises timeout error if agent does not respond' do
      # Use a non-responsive command
      slow_agent = described_class.new('ruby -e "sleep 10"')
      slow_agent.start

      state = { your_id: 'test' }

      expect do
        slow_agent.request_action(state, timeout: 0.1)
      end.to raise_error(JednaTournaments::TimeoutError)

      slow_agent.stop
    end

    it 'raises error if agent returns invalid JSON' do
      bad_agent = described_class.new('ruby -e "puts \"not json\"; STDOUT.flush; sleep 1"')
      bad_agent.start

      state = { your_id: 'test' }

      expect do
        bad_agent.request_action(state)
      end.to raise_error(JednaTournaments::AgentError, /Invalid JSON/)

      bad_agent.stop
    end
  end

  describe '#notify' do
    before { agent.start }

    it 'sends notification to agent' do
      expect { agent.notify_message('Player 2 played r5') }.not_to raise_error
    end

    it 'sends error notification to agent' do
      expect { agent.notify_error('Invalid card') }.not_to raise_error
    end

    it 'sends game end notification to agent' do
      expect do
        agent.notify_game_end('player1', { 'player1' => 0, 'player2' => 15 })
      end.not_to raise_error
    end
  end

  describe 'integration' do
    it 'handles a complete game flow' do
      agent.start

      # Request action
      state = {
        your_id: 'test',
        hand: %w[r5 b7 wd4],
        top_card: 'r3',
        available_actions: %w[play draw]
      }

      action = agent.request_action(state)
      expect(action).to have_key('action')

      # Send notifications
      agent.notify_message('Player 2 played b5')
      agent.notify_error('Cannot play that card')

      # End game
      agent.notify_game_end('player2', { 'test' => 10, 'player2' => 0 })

      # Agent should stop gracefully
      sleep 0.1
      expect(agent.running?).to be false
    end
  end
end
