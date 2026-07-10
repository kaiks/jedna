#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

$stderr.write('x' * 1_000_000)
$stderr.flush

request = gets
if request
  JSON.parse(request)
  puts JSON.generate('action' => 'draw')
  $stdout.flush
end
