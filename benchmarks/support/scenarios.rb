# frozen_string_literal: true

require_relative "database"

module BenchScenarios
  ROOT = File.expand_path("..", __dir__)
  FRAMEWORKS = %w[boto roda sinatra].freeze
  NAMES = %w[hello db].freeze
  DB_SCENARIO = "db"
  HELLO_PATH = "/"
  DB_LOAD_PATH = "/users/500"
  DB_PATH_PREFIX = "/users/"

  def self.app_path(framework, scenario)
    File.join(ROOT, "apps", framework, "#{scenario}.ru")
  end

  def self.load_path(scenario)
    scenario == DB_SCENARIO ? DB_LOAD_PATH : HELLO_PATH
  end

  # Spreads db requests over every seeded user so the lookup is not always the same row.
  def self.path_for(scenario, index)
    return HELLO_PATH unless scenario == DB_SCENARIO

    "#{DB_PATH_PREFIX}#{(index % BenchDatabase::USER_COUNT) + 1}"
  end
end
