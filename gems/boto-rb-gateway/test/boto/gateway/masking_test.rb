# frozen_string_literal: true

require "test_helper"

module Boto
  module Gateway
    class MaskingTest < Minitest::Test
      def test_each_sensitive_word_masks_the_whole_value
        %w[DB_PASSWORD JWT_SECRET API_TOKEN STRIPE_KEY SENTRY_DSN AWS_CREDENTIAL].each do |name|
          assert_equal [Masking::MASK, true], Masking.apply(name, "value-123"), name
        end
      end

      def test_sensitive_words_match_in_any_case
        assert_equal [Masking::MASK, true], Masking.apply("db_password", "value-123")
        assert_equal [Masking::MASK, true], Masking.apply("Api_Token", "value-123")
      end

      def test_url_keeps_everything_but_the_password
        assert_equal [
          "postgres://catalogo:••••••••@localhost:5432/catalogo_dev", true
        ], Masking.apply("DATABASE_URL", "postgres://catalogo:s3cret@localhost:5432/catalogo_dev")
      end

      def test_url_without_password_is_shown_as_is
        assert_equal ["redis://localhost:6379/0", false], Masking.apply("REDIS_URL", "redis://localhost:6379/0")
      end

      def test_url_with_empty_password_is_shown_as_is
        assert_equal ["postgres://catalogo:@localhost/x", false],
                     Masking.apply("DATABASE_URL", "postgres://catalogo:@localhost/x")
      end

      def test_plain_value_is_shown_as_is
        assert_equal ["4101", false], Masking.apply("PORT", "4101")
      end

      def test_value_that_is_not_a_uri_is_shown_as_is
        assert_equal ["not a url %%", false], Masking.apply("NOTE", "not a url %%")
      end
    end
  end
end
