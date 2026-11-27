# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::GenerateCommandTest < Minitest::Test
  SOLUTION_NAME = "shop"
  PROJECT = "catalogo"
  OTHER_PROJECT = "pedidos"
  SCHEMA_PATH = "apps/catalogo/schemas/product_schema.rb"
  SCHEMA_TEST_PATH = "apps/catalogo/test/schemas/product_schema_test.rb"
  MODEL_PATH = "apps/catalogo/models/product.rb"
  MODEL_TEST_PATH = "apps/catalogo/test/models/product_test.rb"

  def setup
    @root = Dir.mktmpdir
    @dir = create_solution(@root)
    @out = StringIO.new
    @err = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_schema_writes_the_source_and_its_test_in_order
    generate(%w[schema catalogo product id:integer name:string tags:[string] available_on:date?])

    assert_equal "create #{SCHEMA_PATH}\ncreate #{SCHEMA_TEST_PATH}\n", @out.string
    assert_equal <<~RUBY, read(SCHEMA_PATH)
      # frozen_string_literal: true

      class Catalogo::ProductSchema < Boto::Schema
        field :id, Integer
        field :name, String
        field :tags, [String]
        field :available_on, Date, required: false
      end
    RUBY
  end

  def test_schema_test_has_flunk_placeholders
    generate(%w[schema catalogo product id:integer])

    assert_equal <<~RUBY, read(SCHEMA_TEST_PATH)
      # frozen_string_literal: true

      require "test_helper"

      class Catalogo::ProductSchemaTest < Minitest::Test
        def test_coerces_a_valid_input
          flunk "write a valid input for Catalogo::ProductSchema.coerce and assert the result"
        end

        def test_rejects_an_invalid_input
          flunk "assert_raises(Boto::Types::Invalid) { Catalogo::ProductSchema.coerce(...) } with an invalid input"
        end
      end
    RUBY
  end

  def test_schema_without_fields_has_an_example_comment
    generate(%w[schema catalogo product])

    assert_equal <<~RUBY, read(SCHEMA_PATH)
      # frozen_string_literal: true

      class Catalogo::ProductSchema < Boto::Schema
        # field :name, String
      end
    RUBY
  end

  def test_schema_name_with_folder_goes_to_a_nested_constant
    generate(%w[schema catalogo orders/item])

    assert_includes @out.string, "create apps/catalogo/schemas/orders/item_schema.rb\n"
    assert_includes read("apps/catalogo/schemas/orders/item_schema.rb"), "class Catalogo::Orders::ItemSchema < Boto::Schema"
    assert_includes read("apps/catalogo/test/schemas/orders/item_schema_test.rb"), "class Catalogo::Orders::ItemSchemaTest"
  end

  def test_model_writes_a_data_with_its_members
    generate(%w[model catalogo product id:integer name:string])

    assert_equal "create #{MODEL_PATH}\ncreate #{MODEL_TEST_PATH}\n", @out.string
    assert_equal <<~RUBY, read(MODEL_PATH)
      # frozen_string_literal: true

      Catalogo::Product = Data.define(:id, :name)
    RUBY
    assert_equal <<~RUBY, read(MODEL_TEST_PATH)
      # frozen_string_literal: true

      require "test_helper"

      class Catalogo::ProductTest < Minitest::Test
        def test_builds_with_its_attributes
          flunk "build Catalogo::Product and assert its attributes"
        end
      end
    RUBY
  end

  def test_model_without_fields_is_a_bare_data
    generate(%w[model catalogo orders/item])

    assert_includes read("apps/catalogo/models/orders/item.rb"), "Catalogo::Orders::Item = Data.define\n"
  end

  def test_skip_tests_writes_only_the_source
    generate(%w[schema catalogo product --skip-tests])

    assert_equal "create #{SCHEMA_PATH}\n", @out.string
    refute File.exist?(File.join(@dir, SCHEMA_TEST_PATH))
  end

  def test_botofile_generators_tests_false_skips_tests_of_every_project
    use_botofile(<<~BOTOFILE)
      solution "shop"

      generators tests: false

      project "catalogo", template: :webapi
      project "pedidos", template: :webapi
    BOTOFILE

    generate(%w[schema catalogo product])

    refute File.exist?(File.join(@dir, SCHEMA_TEST_PATH))
  end

  def test_project_generators_tests_true_overrides_the_solution_default
    use_botofile(<<~BOTOFILE)
      solution "shop"

      generators tests: false

      project "catalogo", template: :webapi
      project "pedidos", template: :webapi, generators: { tests: true }
    BOTOFILE

    generate(%w[schema pedidos product])

    assert File.exist?(File.join(@dir, "apps/pedidos/test/schemas/product_schema_test.rb"))
  end

  def test_existing_file_is_refused_before_anything_is_written
    generate(%w[schema catalogo product --skip-tests])

    error = assert_raises(Boto::CLI::Error) { generate(%w[schema catalogo product]) }

    assert_equal "#{SCHEMA_PATH} already exists (use --force to overwrite)", error.message
    refute File.exist?(File.join(@dir, SCHEMA_TEST_PATH))
  end

  def test_force_overwrites_existing_files
    generate(%w[schema catalogo product id:integer])
    generate(%w[schema catalogo product name:string --force])

    assert_includes read(SCHEMA_PATH), "field :name, String"
    refute_includes read(SCHEMA_PATH), "field :id"
  end

  def test_unknown_project_is_an_error
    error = assert_raises(Boto::CLI::Error) { generate(%w[schema nope product]) }

    assert_equal %(unknown project "nope"), error.message
  end

  def test_unknown_generator_lists_the_available_ones
    error = assert_raises(Boto::CLI::Error) { generate(%w[endpoint catalogo show]) }

    assert_equal %(unknown generator "endpoint" (available: schema, model)), error.message
  end

  def test_missing_arguments_show_usage
    error = assert_raises(Boto::CLI::Error) { generate(%w[schema catalogo]) }

    assert_equal Boto::CLI::Commands::Generate::USAGE, error.message
  end

  def test_invalid_field_is_an_error
    error = assert_raises(Boto::CLI::Error) { generate(%w[schema catalogo product price]) }

    assert_equal %(invalid field "price" (use name:type, e.g. price:float)), error.message
  end

  def test_invalid_name_is_an_error_and_writes_nothing
    error = assert_raises(Boto::CLI::Error) { generate(%w[schema catalogo ../x]) }

    assert_equal %(invalid name "../x" (use lowercase snake_case, folders with /)), error.message
    assert_empty @out.string
  end

  def test_runner_resolves_the_g_alias
    assert_equal 0, runner.run(%w[g schema catalogo product --skip-tests])

    assert_equal "create #{SCHEMA_PATH}\n", @out.string
    assert File.exist?(File.join(@dir, SCHEMA_PATH))
  end

  def test_help_lists_generate_and_describes_the_alias
    assert_equal 0, runner.run(%w[help])
    assert_match(/^  generate\s+Generate a schema/, @out.string)

    @out = StringIO.new
    assert_equal 0, runner.run(%w[help g])
    assert_equal "#{Boto::CLI::Commands::Generate.help}\n", @out.string
  end

  def test_generated_files_load_with_the_project
    generate(%w[schema catalogo product id:integer available_on:date?])
    generate(%w[model catalogo product id:integer name:string])
    boot = Boto::Boot.new(Boto::Botofile.load(File.join(@dir, "Botofile")), root: @dir, warn_output: StringIO.new)

    boot.load(PROJECT)

    assert_equal Boto::Schema, Catalogo::ProductSchema.superclass
    assert_equal %i[id name], Catalogo::Product.members
  ensure
    boot&.shutdown
  end

  private

  def create_solution(root)
    quiet = { out: StringIO.new, err: StringIO.new }
    Boto::CLI::Commands::New.new([SOLUTION_NAME], cwd: root, **quiet).call
    dir = File.join(root, SOLUTION_NAME)
    [PROJECT, OTHER_PROJECT].each do |name|
      Boto::CLI::Commands::Add.new(["webapi", name], cwd: dir, **quiet).call
    end
    dir
  end

  def generate(argv)
    Boto::CLI::Commands::Generate.new(argv, out: @out, err: @err, cwd: @dir).call
  end

  def runner
    Boto::CLI::Runner.new(out: @out, err: @err, cwd: @dir)
  end

  def use_botofile(source)
    File.write(File.join(@dir, "Botofile"), source)
  end

  def read(relative)
    File.read(File.join(@dir, relative))
  end
end
