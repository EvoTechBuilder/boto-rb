# frozen_string_literal: true

require "uri"
require_relative "database"

# Which frameworks run each scenario. db_schema, db_auth and db_auth_redis only exist for boto: the returns DSL and
# the boto security plugins have no equivalent in roda or sinatra, so they measure boto alone.
# db_auth_redis also needs a Redis: when there is none, it is left out of every combination.
module BenchScenarios
  ROOT = File.expand_path("..", __dir__)
  FRAMEWORKS = %w[boto roda sinatra].freeze
  BOTO_ONLY = %w[boto].freeze
  REDIS_SCENARIO = "db_auth_redis"
  FRAMEWORKS_BY_SCENARIO = {
    "hello" => FRAMEWORKS,
    "db" => FRAMEWORKS,
    "db_schema" => BOTO_ONLY,
    "db_auth" => BOTO_ONLY,
    REDIS_SCENARIO => BOTO_ONLY
  }.freeze
  NAMES = FRAMEWORKS_BY_SCENARIO.keys.freeze
  DB_SCENARIOS = %w[db db_schema db_auth db_auth_redis].freeze
  HELLO_PATH = "/"
  DB_LOAD_PATH = "/users/500"
  DB_PATH_PREFIX = "/users/"
  AUTH_TOKEN = "bench-token"
  AUTH_HEADERS = { "Authorization" => "Bearer #{AUTH_TOKEN}" }.freeze
  # Requests of these scenarios must carry the headers. The token matches apps/boto/db_auth*.ru.
  HEADERS_BY_SCENARIO = {
    "db_auth" => AUTH_HEADERS,
    REDIS_SCENARIO => AUTH_HEADERS
  }.freeze
  NO_HEADERS = {}.freeze
  REDIS_DEFAULT_URL = "redis://127.0.0.1:6379/15"
  REDIS_DEFAULT_PORT = 6379
  REDIS_PROBE_TIMEOUT = 0.2
  REDIS_PING_REPLY = "PONG"

  def self.app_path(framework, scenario)
    File.join(ROOT, "apps", framework, "#{scenario}.ru")
  end

  def self.headers_for(scenario) = HEADERS_BY_SCENARIO.fetch(scenario, NO_HEADERS)

  # Rack env keys for the same headers: "Authorization" becomes "HTTP_AUTHORIZATION".
  def self.rack_env_for(scenario)
    headers_for(scenario).to_h { |name, value| ["HTTP_#{name.upcase.tr("-", "_")}", value] }
  end

  def self.frameworks_for(scenario)
    return [] unless scenario_enabled?(scenario)

    FRAMEWORKS_BY_SCENARIO.fetch(scenario)
  end

  def self.scenario_enabled?(scenario) = scenario != REDIS_SCENARIO || redis_available?

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

  # Probed once per process: the answer does not change during a run.
  def self.redis_available?
    return @redis_available if defined?(@redis_available)

    @redis_available = redis_reachable?(redis_url)
  end

  def self.redis_url(env: ENV) = env.fetch("REDIS_URL", REDIS_DEFAULT_URL)

  # Any failure means unavailable, including redis-client missing from the bundle (a LoadError, not a StandardError).
  def self.redis_reachable?(url)
    require "redis-client"
    client = RedisClient.new(url: url, connect_timeout: REDIS_PROBE_TIMEOUT)
    client.call("PING") == REDIS_PING_REPLY
  rescue StandardError, LoadError
    false
  ensure
    client&.close
  end

  # Only host:port goes into messages: the URL may carry a password.
  def self.redis_endpoint(url)
    uri = URI.parse(url)
    "#{uri.host}:#{uri.port || REDIS_DEFAULT_PORT}"
  rescue URI::InvalidURIError
    "invalid REDIS_URL"
  end

  def self.skip_notice
    return if redis_available?

    "#{REDIS_SCENARIO} skipped: Redis not available at #{redis_endpoint(redis_url)}"
  end

  def self.warn_skipped(io: $stderr)
    notice = skip_notice
    io.puts(notice) if notice
  end

  def self.db_scenario?(scenario) = DB_SCENARIOS.include?(scenario)

  def self.load_path(scenario) = db_scenario?(scenario) ? DB_LOAD_PATH : HELLO_PATH

  # Spreads db requests over every seeded user so the lookup is not always the same row.
  def self.path_for(scenario, index)
    return HELLO_PATH unless db_scenario?(scenario)

    "#{DB_PATH_PREFIX}#{(index % BenchDatabase::USER_COUNT) + 1}"
  end
end
