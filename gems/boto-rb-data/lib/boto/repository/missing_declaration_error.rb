# frozen_string_literal: true

module Boto
  class Repository
    # Raised when a repository is used without declaring its entity or its table.
    class MissingDeclarationError < StandardError; end
  end
end
