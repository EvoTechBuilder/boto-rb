# frozen_string_literal: true

module Boto
  class Repository
    # Raised at boot when an entity member has no column in its table, or the table does not exist.
    class SchemaMismatch < StandardError; end
  end
end
