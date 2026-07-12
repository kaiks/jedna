# frozen_string_literal: true

module Jedna
  # Immutable result returned by ActionExecutor.
  ActionResult = Data.define(:success, :code, :message, :action) do
    def self.success(action)
      new(success: true, code: 'ok', message: nil, action: action)
    end

    def self.failure(code, message, action = nil)
      new(success: false, code: code, message: message, action: action)
    end

    def success?
      success
    end

    def error?
      !success
    end
  end
end
