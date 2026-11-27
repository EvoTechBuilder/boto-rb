# frozen_string_literal: true

require "test_helper"

module Boto
  module Gateway
    class EnvRowsTest < Minitest::Test
      SOLUTION = Boto::Env.new({ "REDIS_URL" => "redis://localhost:6379/0", "BOTO_ENV" => "development",
                                 "SENTRY_DSN" => "https://key@sentry.example/1", "PORT" => "4101" },
                               sources: { "REDIS_URL" => ".env", "BOTO_ENV" => "process",
                                          "SENTRY_DSN" => ".env.local", "PORT" => "boto run" },
                               file_keys: %w[REDIS_URL SENTRY_DSN BOTO_ENV PORT])

      PROJECT = Boto::Env.new({ "PORT" => "4101", "DATABASE_URL" => "postgres://u:s3cret@localhost/db",
                                "PAGE_SIZE" => "20" },
                              sources: { "PORT" => ".env", "DATABASE_URL" => "apps/catalogo/.env.development",
                                         "PAGE_SIZE" => "apps/catalogo/.env" },
                              file_keys: %w[DATABASE_URL PAGE_SIZE])

      def test_solution_keys_are_the_root_files_only
        assert_equal %w[REDIS_URL SENTRY_DSN], EnvRows.solution_keys(SOLUTION)
      end

      def test_solution_rows_mask_secrets
        rows = EnvRows.solution(SOLUTION)

        assert_equal ["REDIS_URL", "SENTRY_DSN"], rows.map(&:name)
        assert_equal [".env", ".env.local"], rows.map(&:source)
        assert_equal [false, true], rows.map(&:masked)
        assert_equal "••••••••", rows.last.value
      end

      def test_project_rows_drop_solution_keys_and_keep_port_first
        keys = EnvRows.solution_keys(SOLUTION)
        rows = EnvRows.project(PROJECT, keys)

        assert_equal %w[PORT DATABASE_URL PAGE_SIZE], rows.map(&:name)
        assert_equal [".env", "apps/catalogo/.env.development", "apps/catalogo/.env"], rows.map(&:source)
      end

      def test_project_masks_url_password
        row = EnvRows.project(PROJECT, []).find { |r| r.name == "DATABASE_URL" }

        assert_equal "postgres://u:••••••••@localhost/db", row.value
        assert row.masked
      end

      def test_port_is_listed_even_when_it_is_not_in_a_file
        env = Boto::Env.new({ "PORT" => "61042" }, sources: { "PORT" => "boto run" }, file_keys: [])
        rows = EnvRows.project(env, [])

        assert_equal [["PORT", "61042", "boto run", false]], rows.map { |r| [r.name, r.value, r.source, r.masked] }
      end

      def test_nil_value_is_skipped
        env = Boto::Env.new({}, file_keys: ["MISSING"])

        assert_empty EnvRows.project(env, [])
      end

      def test_missing_env_lists_nothing
        assert_empty EnvRows.solution(nil)
        assert_empty EnvRows.project(nil, [])
      end
    end
  end
end
