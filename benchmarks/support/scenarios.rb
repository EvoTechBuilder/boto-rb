# frozen_string_literal: true

require_relative "database"

# Which frameworks run each scenario. db_schema only exists for boto: the returns DSL has no
# equivalent in roda or sinatra, so it measures boto alone and is not a framework comparison.
module BenchScenarios
  ROOT = File.expand_path("..", __dir__)
  FRAMEWORKS = %w[boto roda sinatra].freeze
  BOTO_ONLY = %w[boto].freeze
  FRAMEWORKS_BY_SCENARIO = {
    "hello" => FRAMEWORKS,
    "db" => FRAMEWORKS,
    "db_schema" => BOTO_ONLY
  }.freeze
  NAMES = FRAMEWORKS_BY_SCENARIO.keys.freeze
  DB_SCENARIOS = %w[db db_schema].freeze
  HELLO_PATH = "/"
  DB_LOAD_PATH = "/users/500"
  DB_PATH_PREFIX = "/users/"

  def self.app_path(framework, scenario)
    File.join(ROOT, "apps", framework, "#{scenario}.ru")
  end

  def self.frameworks_for(scenario) = FRAMEWORKS_BY_SCENARIO.fetch(scenario)

  def self.scenarios_for(framework) = NAMES.select { |scenario| frameworks_for(scenario).include?(framework) }

  def self.combinations
    FRAMEWORKS.flat_map { |framework| scenarios_for(framework).map { |scenario| [framework, scenario] } }
  end

  # { framework => { scenario => yield(framework, scenario) } }, only over supported combinations.
  def self.matrix
    FRAMEWORKS.to_h do |framework|
      [framework, scenarios_for(framework).to_h { |scenario| [scenario, yield(framework, scenario)] }]
    end
  end

  def self.db_scenario?(scenario) = DB_SCENARIOS.include?(scenario)

  def self.load_path(scenario) = db_scenario?(scenario) ? DB_LOAD_PATH : HELLO_PATH

  # Spreads db requests over every seeded user so the lookup is not always the same row.
  def self.path_for(scenario, index)
    return HELLO_PATH unless db_scenario?(scenario)

    "#{DB_PATH_PREFIX}#{(index % BenchDatabase::USER_COUNT) + 1}"
  end
end
