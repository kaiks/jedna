# frozen_string_literal: true

require 'monitor'
require_relative 'core/game'

# Adds reentrant synchronization around the public Jedna::Game API.
module ThreadSafeGame
  def self.included(base)
    synchronized_api = Module.new do
      define_method(:initialize) do |*args, **kwargs, &block|
        @__monitor = Monitor.new
        super(*args, **kwargs, &block)
      end

      Jedna::Game.public_instance_methods(false).each do |method_name|
        next if method_name == :initialize

        define_method(method_name) do |*args, **kwargs, &block|
          @__monitor.synchronize do
            super(*args, **kwargs, &block)
          end
        end
      end
    end

    base.prepend(synchronized_api)
  end
end
