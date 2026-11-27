# frozen_string_literal: true

module Boto
  module CLI
    # Detects files created, changed or removed by comparing mtime snapshots, so a dev reload runs only on changes.
    class FileWatcher
      def initialize(patterns, glob: Dir.method(:glob), mtime: File.method(:mtime))
        @patterns = patterns
        @glob = glob
        @mtime = mtime
        @snapshot = take_snapshot
        @changes = 0
      end

      attr_reader :changes

      def changed?
        current = take_snapshot
        @changes = changed_paths_count(@snapshot, current)
        @snapshot = current
        @changes.positive?
      end

      private

      def changed_paths_count(previous, current)
        (previous.keys | current.keys).count { |path| previous[path] != current[path] }
      end

      def take_snapshot
        candidate_paths.each_with_object({}) do |path, snapshot|
          # A file deleted between the glob and the stat is simply missing from the snapshot, which reads as removed.
          snapshot[path] = @mtime.call(path)
        rescue Errno::ENOENT
          nil
        end
      end

      def candidate_paths
        @patterns.flat_map { |pattern| @glob.call(pattern) }.uniq
      end
    end
  end
end
