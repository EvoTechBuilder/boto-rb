# frozen_string_literal: true

require "test_helper"

class Boto::Redis::RateLimitStore::CloseTest < Minitest::Test
  class SpyClient
    attr_reader :close_calls

    def initialize
      @close_calls = 0
    end

    def close
      @close_calls += 1
    end
  end

  def test_close_leaves_an_injected_client_open
    client = SpyClient.new
    store = Boto::Redis::RateLimitStore.new(client: client)

    store.close

    assert_equal 0, client.close_calls
  end
end
