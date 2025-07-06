#!/usr/bin/env ruby
# Simple agent that echoes back predetermined responses for testing

require 'json'

responses = {
  'request_action' => { 'action' => 'draw' },
  'notification' => nil,
  'error' => nil,
  'game_end' => :exit
}

# Allow override via environment variable
if ENV['AGENT_RESPONSE']
  responses['request_action'] = JSON.parse(ENV['AGENT_RESPONSE'])
end

loop do
  input = gets
  break if input.nil?
  
  data = JSON.parse(input)
  response = responses[data['type']]
  
  if response == :exit
    break
  elsif response
    puts JSON.generate(response)
    STDOUT.flush
  end
end