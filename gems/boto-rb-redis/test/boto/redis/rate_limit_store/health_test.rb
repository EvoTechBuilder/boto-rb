# frozen_string_literal: true

require "test_helper"

class Boto::Redis::RateLimitStore::HealthTest < Minitest::Test
  class PongClient
    attr_reader :commands

    def initialize
      @commands = []
    end

    def call(*command)
      @commands << command
      "PONG"
    end
  end

  class OtherReplyClient
    def call(*) = "LOADING"
  end

  class UnreachableClient
    def call(*)
      raise ::RedisClient::CannotConnectError, "connection refused"
    end
  end

  class ExhaustedPoolClient
    def call(*)
      raise ConnectionPool::TimeoutError, "timed out"
    end
  end

  def test_healthy_when_redis_answers_pong
    client = PongClient.new

    assert build_store(client).healthy?
    assert_equal [["PING"]], client.commands
  end

  def test_unhealthy_when_redis_answers_something_else
    refute build_store(OtherReplyClient.new).healthy?
  end

  def test_unhealthy_when_redis_is_unreachable
    refute build_store(UnreachableClient.new).healthy?
  end

  def test_unhealthy_when_the_pool_is_exhausted
    refute build_store(ExhaustedPoolClient.new).healthy?
  end

  private

  def build_store(client)
    Boto::Redis::RateLimitStore.new(client: client)
  end
end
