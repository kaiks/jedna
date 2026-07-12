# frozen_string_literal: true

require 'monitor'
require_relative 'core/game'

# Adds reentrant synchronization around the public Jedna::Game API.
module ThreadSafeGame
  def self.included(base)
    base.prepend(synchronized_api)
  end

  def self.synchronized_api
    Module.new.tap do |api|
      define_synchronized_initializer(api)
      define_synchronize(api)
      define_synchronized_game_methods(api)
    end
  end

  def self.define_synchronized_initializer(api)
    api.define_method(:initialize) do |*args, **kwargs, &block|
      @__monitor = Monitor.new
      super(*args, **kwargs, &block)
    end
  end

  def self.define_synchronize(api)
    api.define_method(:synchronize) { |&block| @__monitor.synchronize(&block) }
  end

  def self.define_synchronized_game_methods(api)
    Jedna::Game.public_instance_methods(false).each do |method_name|
      next if method_name == :initialize

      api.define_method(method_name) do |*args, **kwargs, &block|
        @__monitor.synchronize { super(*args, **kwargs, &block) }
      end
    end
  end
  private_class_method :synchronized_api, :define_synchronized_initializer, :define_synchronize,
                       :define_synchronized_game_methods
end
