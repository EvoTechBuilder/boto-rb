# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"
require "sequel"
require "boto/database"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::DbCommandTest < Minitest::Test
  DATABASE_PROJECT = "catalogo"
  PLAIN_PROJECT = "pedidos"
  FIRST_MIGRATION = "20260101000000_create_products.rb"
  SECOND_MIGRATION = "20260102000000_create_prices.rb"
  CREATE_PRODUCTS = "create_table(:products) { primary_key :id }"
  CREATE_PRICES = "create_table(:prices) { primary_key :id }"
  DB_FILE = "db.sqlite3"

  def setup
    @root = Dir.mktmpdir
    @dir = create_solution(@root)
    @out = StringIO.new
    @err = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_migrate_applies_pending_migrations_once
    use_database
    write_migration(FIRST_MIGRATION, CREATE_PRODUCTS)
    write_migration(SECOND_MIGRATION, CREATE_PRICES)

    assert_equal 0, db(%w[migrate]).call
    assert_equal "#{DATABASE_PROJECT}: migrated #{FIRST_MIGRATION}\n" \
                 "#{DATABASE_PROJECT}: migrated #{SECOND_MIGRATION}\n", @out.string
    assert_equal %i[prices products], tables.sort

    @out = StringIO.new
    db(%w[migrate]).call
    assert_equal "#{DATABASE_PROJECT}: up to date\n", @out.string
  end

  def test_rollback_undoes_the_newest_migration_by_default
    use_database
    write_migration(FIRST_MIGRATION, CREATE_PRODUCTS)
    write_migration(SECOND_MIGRATION, CREATE_PRICES)
    db(%w[migrate]).call
    @out = StringIO.new

    assert_equal 0, db(%w[rollback catalogo]).call
    assert_equal "#{DATABASE_PROJECT}: rolled back #{SECOND_MIGRATION}\n", @out.string
    assert_equal [:products], tables
  end

  def test_rollback_accepts_steps
    use_database
    write_migration(FIRST_MIGRATION, CREATE_PRODUCTS)
    write_migration(SECOND_MIGRATION, CREATE_PRICES)
    db(%w[migrate]).call
    @out = StringIO.new

    db(%w[rollback catalogo --steps 2]).call
    assert_equal "#{DATABASE_PROJECT}: rolled back #{SECOND_MIGRATION}\n" \
                 "#{DATABASE_PROJECT}: rolled back #{FIRST_MIGRATION}\n", @out.string
    assert_empty tables
  end

  def test_rollback_with_nothing_applied_says_so
    use_database
    write_migration(FIRST_MIGRATION, CREATE_PRODUCTS)

    db(%w[rollback catalogo]).call
    assert_equal "#{DATABASE_PROJECT}: nothing to roll back\n", @out.string
  end

  def test_status_lists_each_migration_with_its_state
    use_database
    write_migration(FIRST_MIGRATION, CREATE_PRODUCTS)
    write_migration(SECOND_MIGRATION, CREATE_PRICES)
    db(%w[migrate]).call
    db(%w[rollback catalogo]).call
    @out = StringIO.new

    db(%w[status]).call
    assert_equal "#{DATABASE_PROJECT}  up    #{FIRST_MIGRATION}\n" \
                 "#{DATABASE_PROJECT}  down  #{SECOND_MIGRATION}\n", @out.string
  end

  def test_status_without_migrations_says_so
    use_database

    db(%w[status catalogo]).call
    assert_equal "#{DATABASE_PROJECT}: no migrations\n", @out.string
  end

  def test_without_projects_database_reports_it
    db(%w[migrate]).call
    assert_equal "no projects with :database\n", @out.string
  end

  def test_named_project_without_database_is_an_error
    use_database
    error = assert_raises(Boto::CLI::Error) { db(%w[migrate pedidos]).call }

    assert_equal %(project "pedidos" has no :database (add app.use :database, url: ... to its config/app.rb)),
                 error.message
  end

  def test_unknown_project_is_an_error
    error = assert_raises(Boto::CLI::Error) { db(%w[migrate nope]).call }

    assert_equal %(unknown project "nope"), error.message
  end

  def test_missing_subcommand_or_unknown_one_shows_usage
    usage = "Usage: boto db <migrate|rollback|status> [project] [--steps N]"

    assert_equal usage, assert_raises(Boto::CLI::Error) { db([]).call }.message
    assert_equal usage, assert_raises(Boto::CLI::Error) { db(%w[reset]).call }.message
  end

  def test_rollback_without_project_shows_usage
    error = assert_raises(Boto::CLI::Error) { db(%w[rollback]).call }

    assert_equal "Usage: boto db <migrate|rollback|status> [project] [--steps N]", error.message
  end

  def test_invalid_steps_are_refused
    use_database

    zero = assert_raises(Boto::CLI::Error) { db(%w[rollback catalogo --steps 0]).call }
    assert_equal "steps must be a positive Integer", zero.message
    text = assert_raises(Boto::CLI::Error) { db(%w[rollback catalogo --steps many]).call }
    assert_match(/invalid argument/, text.message)
    other = assert_raises(Boto::CLI::Error) { db(%w[migrate catalogo --steps 2]).call }
    assert_equal "--steps only applies to rollback", other.message
  end

  def test_missing_gem_asks_for_it
    use_database
    missing = -> { raise LoadError, "cannot load such file -- boto/database" }

    error = assert_raises(Boto::CLI::Error) { db(%w[migrate], require_library: missing).call }
    assert_equal %(boto db needs the boto-rb-data gem: add gem "boto-rb-data" to the Gemfile), error.message
  end

  def test_errors_never_show_the_database_url
    use_database(url: "postgres://app:s3cret@127.0.0.1:1/shop")

    error = assert_raises(Boto::CLI::Error) { db(%w[migrate]).call }
    assert_match(/\A#{DATABASE_PROJECT}: /, error.message)
    refute_includes error.message, "s3cret"
  end

  def test_broken_migration_is_a_one_line_error
    use_database
    write_migration(FIRST_MIGRATION, "run 'NOT SQL'")

    error = assert_raises(Boto::CLI::Error) { db(%w[migrate]).call }
    assert_match(/\A#{DATABASE_PROJECT}: /, error.message)
  end

  # boto db builds only the :database plugin, so the tokens of :auth are not needed to migrate.
  def test_migrate_does_not_need_the_secrets_of_other_plugins
    use_database
    write_migration(FIRST_MIGRATION, CREATE_PRODUCTS)

    assert_equal 0, db(%w[migrate], env: {}).call
  end

  private

  def db(argv, env: {}, require_library: -> {})
    Boto::CLI::Commands::Db.new(argv, out: @out, err: @err, cwd: @dir, env: env, require_library: require_library)
  end

  def create_solution(root)
    quiet = { out: StringIO.new, err: StringIO.new }
    Boto::CLI::Commands::New.new(%w[shop], cwd: root, **quiet).call
    dir = File.join(root, "shop")
    [DATABASE_PROJECT, PLAIN_PROJECT].each do |name|
      Boto::CLI::Commands::Add.new(%w[webapi] + [name], cwd: dir, **quiet).call
    end
    dir
  end

  # The database lives in a temporary file, so the migrations can be checked with a real SQLite.
  def use_database(url: "sqlite://#{File.join(@root, DB_FILE)}")
    path = File.join(@dir, "apps", DATABASE_PROJECT, "config", "environments", "development.rb")
    File.write(path, <<~RUBY)
      # frozen_string_literal: true

      Boto.configure do |app|
        app.use :database, url: #{url.inspect}
      end
    RUBY
  end

  def write_migration(name, body)
    dir = File.join(@dir, "apps", DATABASE_PROJECT, "db", "migrations")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, name), <<~RUBY)
      # frozen_string_literal: true

      Sequel.migration do
        change do
          #{body}
        end
      end
    RUBY
  end

  def tables
    database = Sequel.sqlite(File.join(@root, DB_FILE))
    database.tables - [:schema_migrations]
  ensure
    database&.disconnect
  end
end
