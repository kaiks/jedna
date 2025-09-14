#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple agent that echoes back predetermined responses for testing

require 'json'

responses = {
  'request_action' => { 'action' => 'draw' },
  'notification' => nil,
  'error' => nil,
  'game_end' => :exit
}

# Allow override via environment variable
responses['request_action'] = JSON.parse(ENV['AGENT_RESPONSE']) if ENV['AGENT_RESPONSE']

loop do
  input = gets
  break if input.nil?

  data = JSON.parse(input)
  response = responses[data['type']]

  if response == :exit
    break
  elsif response
    puts JSON.generate(response)
    $stdout.flush
  end
end
