# frozen_string_literal: true

module Jedna
  # Immutable result returned by ActionExecutor.
  ActionResult = Data.define(:success, :code, :message, :action) do
    def success?
      success
    end

    def error?
      !success
    end
  end
end
