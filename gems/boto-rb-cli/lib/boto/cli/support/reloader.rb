# frozen_string_literal: true

require "json"

module Boto
  module CLI
    # Rebuilds the solution on the first request after a change, so development never restarts the process.
    class Reloader
      MONOTONIC_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      MILLISECONDS = 1000
      GEMFILE = "Gemfile"
      BOTOFILE = "Botofile"
      GEMFILE_CHANGED = "Gemfile changed: restart boto run"
      BOTOFILE_CHANGED = "Botofile changed: restart boto run"
      SOLUTION_ENV = ".env*"
      SOLUTION_ENV_CHANGED = ".env changed: restart boto run"
      RELOADED = "Reloaded in %d ms (%d %s changed)"
      FAILED = "Reload failed: %s: %s"
      BACKTRACE_LINES = 5
      PROBLEM_STATUS = 500
      PROBLEM_TYPE = "application/problem+json"
      PROBLEM_TITLE = "Reload failed"
      PROBLEM_ABOUT = "about:blank"
      CONTENT_TYPE = "content-type"

      # process_env is the snapshot taken before any .env was read, so every rebuilt Boot sees the same process values.
      def initialize(root:, ports:, env_name:, out:, err:, load_solution:, watcher:,
                     manifest_watchers: {}, clock: MONOTONIC_CLOCK, env: ENV, process_env: nil)
        @root, @ports, @env_name = root, ports, env_name
        @env = env
        @process_env = process_env
        @out, @err, @load_solution, @watcher = out, err, load_solution, watcher
        @manifest_watchers, @clock = manifest_watchers, clock
        @mutex = Thread::Mutex.new
        @draining = false
        @reload_pending = false
        @fresh_solution = nil
        @error_app = nil
        @solution = load_solution.call
        build
      rescue StandardError, ScriptError
        @boot&.shutdown
        raise
      end

      def app_for(port)
        ReloadingApp.new(self, port)
      end

      # Checks for changes under the mutex, so a request waits for a reload in progress instead of using a stopped app.
      def current(port)
        @mutex.synchronize { refresh } unless @draining
        @error_app || @apps.fetch(port)
      end

      def drain!
        @mutex.synchronize do
          @draining = true
          @apps.each_value { |app| app.drain! if app.respond_to?(:drain!) }
        end
      end

      def shutdown
        @mutex.synchronize { @boot.shutdown }
      end

      private

      def refresh
        check_manifests
        code_changed = @watcher.changed?
        reload if code_changed || @reload_pending
      end

      def check_manifests
        @err.puts GEMFILE_CHANGED if manifest_changed?(GEMFILE)
        @err.puts SOLUTION_ENV_CHANGED if manifest_changed?(SOLUTION_ENV)
        check_botofile if manifest_changed?(BOTOFILE)
      end

      def manifest_changed?(name)
        watcher = @manifest_watchers[name]
        watcher ? watcher.changed? : false
      end

      # Adding, removing or retemplating a project needs a restart (the ports are already bound); refs reload.
      def check_botofile
        fresh = fresh_solution
        return @err.puts(BOTOFILE_CHANGED) if fresh && templates_by_name(fresh) != templates_by_name(@solution)

        @fresh_solution = fresh
        @reload_pending = true
      end

      # A broken Botofile is left to the reload, which reports the error in the response.
      def fresh_solution
        @load_solution.call
      rescue StandardError, ScriptError
        nil
      end

      def templates_by_name(solution)
        solution.projects.to_h { |project| [project.name, project.template] }
      end

      def reload
        started = @clock.call
        changes = @watcher.changes
        @reload_pending = false
        @boot.shutdown
        fresh, @fresh_solution = @fresh_solution, nil
        @solution = fresh || @load_solution.call
        build
        @error_app = nil
        report_reloaded(changes, ((@clock.call - started) * MILLISECONDS).round)
      rescue StandardError, ScriptError => e
        fail_reload(e)
      end

      # Assigns @boot before the apps are built, so a partial boot is still shut down by the next #shutdown.
      def build
        @boot = Boto::Boot.new(@solution, root: @root, env: @env, process_env: @process_env)
        @apps = @ports.to_h { |name, port| [port, @boot.app(name, env_name: @env_name)] }
      end

      def report_reloaded(changes, elapsed_ms)
        @out.puts format(RELOADED, elapsed_ms, changes, changes == 1 ? "file" : "files")
      end

      def fail_reload(error)
        @error_app = problem_app(error)
        @err.puts format(FAILED, error.class, error.message)
        Array(error.backtrace).first(BACKTRACE_LINES).each { |line| @err.puts "  #{line}" }
      end

      def problem_app(error)
        body = JSON.generate(type: PROBLEM_ABOUT, title: PROBLEM_TITLE, status: PROBLEM_STATUS,
                             detail: "#{error.class}: #{error.message}").freeze
        ->(_env) { [PROBLEM_STATUS, { CONTENT_TYPE => PROBLEM_TYPE }, [body]] }
      end
    end
  end
end
