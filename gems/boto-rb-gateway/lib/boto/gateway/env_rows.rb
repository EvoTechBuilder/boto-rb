# frozen_string_literal: true

module Boto
  module Gateway
    # The variables the panel lists: the solution's root files first, then what each project adds.
    module EnvRows
      Row = Data.define(:name, :value, :source, :masked)

      PORT = "PORT"
      PROCESS_SOURCE = "process"
      BOTO_RUN_SOURCE = "boto run"
      NO_ENV = Boto::Env.new({})

      module_function

      def solution(env)
        env = normalize(env)
        rows(env, solution_keys(env))
      end

      # Keys whose source is a file in the solution root: no "/" in the path and not a process-level source.
      def solution_keys(env)
        env = normalize(env)
        env.file_keys.select { |key| root_file?(env.source(key)) }
      end

      def project(env, solution_keys)
        env = normalize(env)
        rows(env, [PORT] | (env.file_keys - solution_keys))
      end

      # An app without an env (no .env files loaded) lists nothing.
      def normalize(env) = env || NO_ENV

      def root_file?(source)
        source && !source.include?("/") && ![PROCESS_SOURCE, BOTO_RUN_SOURCE].include?(source)
      end

      def rows(env, keys)
        keys.filter_map { |key| row(env, key) }
      end

      def row(env, key)
        value = env[key]
        return if value.nil?

        shown, masked = Masking.apply(key, value)
        Row.new(name: key, value: shown, source: env.source(key), masked: masked)
      end
    end
  end
end
