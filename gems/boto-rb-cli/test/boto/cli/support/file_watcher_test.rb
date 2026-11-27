# frozen_string_literal: true

require "test_helper"

class Boto::CLI::FileWatcherTest < Minitest::Test
  PATTERN = "/sol/apps/pedidos/**/*.rb"
  SECOND = Time.at(2)

  def test_reports_no_change_when_nothing_moved
    files = {"/a.rb" => Time.at(1)}
    watcher = build(files)

    refute watcher.changed?
    assert_equal 0, watcher.changes
  end

  def test_reports_a_changed_mtime_only_once
    files = {"/a.rb" => Time.at(1)}
    watcher = build(files)

    files["/a.rb"] = SECOND

    assert watcher.changed?
    assert_equal 1, watcher.changes
    refute watcher.changed?
    assert_equal 0, watcher.changes
  end

  def test_reports_a_new_file
    files = {"/a.rb" => Time.at(1)}
    watcher = build(files)

    files["/b.rb"] = Time.at(1)

    assert watcher.changed?
    assert_equal 1, watcher.changes
  end

  def test_reports_a_removed_file
    files = {"/a.rb" => Time.at(1)}
    watcher = build(files)

    files.delete("/a.rb")

    assert watcher.changed?
    assert_equal 1, watcher.changes
  end

  def test_treats_a_file_deleted_between_glob_and_stat_as_removed
    files = {"/a.rb" => Time.at(1), "/gone.rb" => Time.at(1)}
    deleted = []
    watcher = build(files, mtime: ->(path) { raise Errno::ENOENT if deleted.include?(path); files.fetch(path) })

    deleted << "/gone.rb"

    assert_predicate watcher, :changed?
    assert_equal 1, watcher.changes
  end

  def test_counts_every_path_that_changed
    files = {"/a.rb" => Time.at(1), "/b.rb" => Time.at(1), "/c.rb" => Time.at(1)}
    watcher = build(files)

    files["/a.rb"] = SECOND
    files.delete("/b.rb")

    assert watcher.changed?
    assert_equal 2, watcher.changes
  end

  def test_joins_patterns_and_counts_a_path_repeated_across_them_once
    files = {"/a.rb" => Time.at(1), "/b.rb" => Time.at(1)}
    matches = {"/sol/a/**/*.rb" => ["/a.rb", "/b.rb"], "/sol/b/**/*.rb" => ["/b.rb"]}
    watcher = build(files, patterns: matches.keys, glob: ->(pattern) { matches.fetch(pattern) })

    files["/b.rb"] = SECOND

    assert watcher.changed?
    assert_equal 1, watcher.changes
  end

  private

  def build(files, patterns: [PATTERN], glob: nil, mtime: nil)
    glob ||= ->(_pattern) { files.keys }
    mtime ||= ->(path) { files.fetch(path) { raise Errno::ENOENT } }

    Boto::CLI::FileWatcher.new(patterns, glob: glob, mtime: mtime)
  end
end
