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
  ENDPOINT_PATH = "apps/catalogo/endpoints/products/show.rb"
  ENDPOINT_TEST_PATH = "apps/catalogo/test/endpoints/products/show_test.rb"
  CREATE_ENDPOINT_PATH = "apps/catalogo/endpoints/products/create.rb"
  CREATE_ENDPOINT_TEST_PATH = "apps/catalogo/test/endpoints/products/create_test.rb"
  SEARCH_ENDPOINT_TEST_PATH = "apps/catalogo/test/endpoints/products/search_test.rb"
  OPERATION_PATH = "apps/catalogo/operations/create_product.rb"
  OPERATION_TEST_PATH = "apps/catalogo/test/operations/create_product_test.rb"

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
    error = assert_raises(Boto::CLI::Error) { generate(%w[widget catalogo show]) }

    assert_equal %(unknown generator "widget" (available: schema, model, endpoint, operation)), error.message
  end

  def test_unknown_field_type_is_refused_before_anything_is_written
    error = assert_raises(Boto::CLI::Error) { generate(%w[schema catalogo product price:decimal]) }

    assert_equal %(unknown type "decimal" for field "price" (use string, integer, float, boolean, date, time, [type] or the name of a schema in schemas/)), error.message
    refute File.exist?(File.join(@dir, SCHEMA_PATH))
  end

  def test_field_referencing_an_existing_schema_is_accepted
    generate(%w[schema catalogo category --skip-tests])
    generate(%w[schema catalogo product category:category categories:[category]])

    assert_includes read(SCHEMA_PATH), "field :category, Catalogo::CategorySchema"
    assert_includes read(SCHEMA_PATH), "field :categories, [Catalogo::CategorySchema]"
  end

  def test_endpoint_writes_the_route_with_its_typed_path_param_and_schema
    generate(%w[schema catalogo product --skip-tests])
    generate(%w[endpoint catalogo products/show get /products/:id id:integer --returns product])

    assert_equal <<~RUBY, read(ENDPOINT_PATH)
      # frozen_string_literal: true

      class Catalogo::Products::Show < Boto::Endpoint
        get "/products/:id"
        param :id, Integer
        returns Catalogo::ProductSchema

        def call(id:)
          raise NotImplementedError, "Catalogo::Products::Show#call"
        end
      end
    RUBY
  end

  def test_endpoint_path_param_defaults_to_string
    generate(%w[endpoint catalogo products/show get /products/:id])

    assert_includes read(ENDPOINT_PATH), %(  param :id, String\n)
  end

  def test_endpoint_with_body_and_list_response
    generate(%w[schema catalogo product --skip-tests])
    generate(%w[schema catalogo create_product --skip-tests])
    generate(%w[endpoint catalogo products/create post /products --body create_product --returns [product]])

    assert_equal <<~RUBY, read(CREATE_ENDPOINT_PATH)
      # frozen_string_literal: true

      class Catalogo::Products::Create < Boto::Endpoint
        post "/products"
        body Catalogo::CreateProductSchema
        returns [Catalogo::ProductSchema]

        def call(body:)
          raise NotImplementedError, "Catalogo::Products::Create#call"
        end
      end
    RUBY
  end

  def test_endpoint_without_params_or_schemas_has_a_bare_call
    generate(%w[endpoint catalogo ping get /ping])

    assert_equal <<~RUBY, read("apps/catalogo/endpoints/ping.rb")
      # frozen_string_literal: true

      class Catalogo::Ping < Boto::Endpoint
        get "/ping"

        def call
          raise NotImplementedError, "Catalogo::Ping#call"
        end
      end
    RUBY
  end

  def test_endpoint_test_sends_the_bearer_token_when_auth_is_enabled
    generate(%w[endpoint catalogo products/show get /products/:id id:integer])

    assert_equal <<~RUBY, read(ENDPOINT_TEST_PATH)
      # frozen_string_literal: true

      require "test_helper"

      class Catalogo::Products::ShowTest < Minitest::Test
        def test_get_products_id
          response = Rack::MockRequest.new(APP).get("/products/1", "HTTP_AUTHORIZATION" => "Bearer test-token")
          flunk "assert the response of GET /products/:id (status \#{response.status})"
        end
      end
    RUBY
  end

  def test_endpoint_test_has_no_token_without_the_auth_plugin
    File.write(File.join(@dir, "apps/catalogo/config/app.rb"), "Boto.configure do |app|\nend\n")

    generate(%w[endpoint catalogo ping get /ping])

    assert_includes read("apps/catalogo/test/endpoints/ping_test.rb"),
                    %(response = Rack::MockRequest.new(APP).get("/ping")\n)
  end

  def test_endpoint_test_sends_input_for_writing_and_query_verbs
    generate(%w[schema catalogo create_product --skip-tests])
    generate(%w[endpoint catalogo products/create post /products --body create_product])
    generate(%w[endpoint catalogo products/search query /products/search])

    assert_includes read(CREATE_ENDPOINT_TEST_PATH),
                    %(Rack::MockRequest.new(APP).post("/products", input: "{}", "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer test-token"))
    assert_includes read(SEARCH_ENDPOINT_TEST_PATH),
                    %(Rack::MockRequest.new(APP).request("QUERY", "/products/search", input: "{}", "HTTP_AUTHORIZATION" => "Bearer test-token"))
  end

  def test_endpoint_refuses_an_unknown_body_schema_before_writing
    error = assert_raises(Boto::CLI::Error) { generate(%w[endpoint catalogo products/create post /products --body prodcut]) }

    assert_equal %(unknown schema "prodcut" for --body (no schemas/prodcut_schema.rb in catalogo)), error.message
    refute File.exist?(File.join(@dir, CREATE_ENDPOINT_PATH))
    assert_empty @out.string
  end

  def test_endpoint_refuses_an_unknown_list_schema_for_returns_before_writing
    error = assert_raises(Boto::CLI::Error) { generate(%w[endpoint catalogo products/show get /products/:id --returns [prodcut]]) }

    assert_equal %(unknown schema "prodcut" for --returns (no schemas/prodcut_schema.rb in catalogo)), error.message
    refute File.exist?(File.join(@dir, ENDPOINT_PATH))
    assert_empty @out.string
  end

  def test_operation_refuses_fields
    error = assert_raises(Boto::CLI::Error) { generate(%w[operation catalogo create_product name:string]) }

    assert_equal "operation takes no fields", error.message
    refute File.exist?(File.join(@dir, OPERATION_PATH))
  end

  def test_body_and_returns_are_refused_outside_endpoints
    schema_error = assert_raises(Boto::CLI::Error) { generate(%w[schema catalogo product --body create_product]) }
    operation_error = assert_raises(Boto::CLI::Error) { generate(%w[operation catalogo create_product --returns product]) }

    assert_equal "--body and --returns only apply to endpoint", schema_error.message
    assert_equal "--body and --returns only apply to endpoint", operation_error.message
    refute File.exist?(File.join(@dir, SCHEMA_PATH))
    refute File.exist?(File.join(@dir, OPERATION_PATH))
  end

  def test_endpoint_refuses_an_unknown_verb
    error = assert_raises(Boto::CLI::Error) { generate(%w[endpoint catalogo products/show GET /products/:id]) }

    assert_equal %(unknown verb "GET" (available: get, post, put, patch, delete, query)), error.message
  end

  def test_endpoint_refuses_a_path_without_a_leading_slash
    error = assert_raises(Boto::CLI::Error) { generate(%w[endpoint catalogo products/show get products/:id]) }

    assert_equal %(invalid path "products/:id" (start with / and use letters, digits, _ - / : .)), error.message
  end

  def test_endpoint_refuses_a_field_that_is_not_a_path_param
    error = assert_raises(Boto::CLI::Error) { generate(%w[endpoint catalogo products/show get /products/:id price:float]) }

    assert_equal %(field "price" is not a path param of /products/:id), error.message
  end

  def test_endpoint_refuses_a_non_scalar_path_param
    generate(%w[schema catalogo product --skip-tests])
    error = assert_raises(Boto::CLI::Error) { generate(%w[endpoint catalogo products/show get /products/:id id:product]) }

    assert_equal %(path param "id" must be a scalar type (string, integer, float, boolean, date, time)), error.message
  end

  def test_endpoint_is_refused_for_a_library
    add_library("dominio")

    error = assert_raises(Boto::CLI::Error) { generate(%w[endpoint dominio products/show get /products/:id]) }

    assert_equal "endpoints are only generated for HTTP projects (dominio is a library)", error.message
  end

  def test_operation_writes_the_module_and_its_test
    generate(%w[operation catalogo create_product])

    assert_equal "create #{OPERATION_PATH}\ncreate #{OPERATION_TEST_PATH}\n", @out.string
    assert_equal <<~RUBY, read(OPERATION_PATH)
      # frozen_string_literal: true

      class Catalogo::CreateProduct < Boto::Operation
        def call
          raise NotImplementedError, "Catalogo::CreateProduct#call"
        end
      end
    RUBY
    assert_equal <<~RUBY, read(OPERATION_TEST_PATH)
      # frozen_string_literal: true

      require "test_helper"

      class Catalogo::CreateProductTest < Minitest::Test
        def test_call
          flunk "call Catalogo::CreateProduct.call(input) and assert result.success? and result.value"
        end
      end
    RUBY
  end

  def test_operation_refuses_a_name_with_a_folder
    error = assert_raises(Boto::CLI::Error) { generate(%w[operation catalogo products/create]) }

    assert_equal "operation names are verbs without folders, e.g. create_product", error.message
    assert_empty @out.string
  end

  def test_operation_is_allowed_in_a_library
    add_library("dominio")

    generate(%w[operation dominio create_product --skip-tests])

    assert File.exist?(File.join(@dir, "libs/dominio/operations/create_product.rb"))
  end

  def test_operation_is_refused_when_a_model_has_the_same_constant
    generate(%w[model catalogo create_product --skip-tests])

    error = assert_raises(Boto::CLI::Error) { generate(%w[operation catalogo create_product]) }

    assert_equal "Catalogo::CreateProduct already exists in apps/catalogo/models/create_product.rb", error.message
    refute File.exist?(File.join(@dir, OPERATION_PATH))
  end

  def test_endpoint_is_refused_when_an_operation_has_the_same_constant
    generate(%w[operation catalogo create_product --skip-tests])

    error = assert_raises(Boto::CLI::Error) { generate(%w[endpoint catalogo create_product get /x]) }

    assert_equal "Catalogo::CreateProduct already exists in apps/catalogo/operations/create_product.rb", error.message
  end

  def test_force_replaces_the_operation_but_not_a_clash_in_another_folder
    generate(%w[operation catalogo create_product --skip-tests])
    generate(%w[operation catalogo create_product --force])
    File.delete(File.join(@dir, OPERATION_PATH))
    generate(%w[model catalogo create_product --skip-tests])

    error = assert_raises(Boto::CLI::Error) { generate(%w[operation catalogo create_product --force]) }

    assert_equal "Catalogo::CreateProduct already exists in apps/catalogo/models/create_product.rb", error.message
  end

  def test_generated_endpoint_and_operation_load_with_the_project
    generate(%w[schema catalogo product id:integer --skip-tests])
    generate(%w[operation catalogo create_product --skip-tests])
    generate(%w[endpoint catalogo products/show get /products/:id id:integer --returns product --skip-tests])
    boot = Boto::Boot.new(Boto::Botofile.load(File.join(@dir, "Botofile")), root: @dir, warn_output: StringIO.new)

    app = boot.app(PROJECT, env_name: "development")

    assert_includes app.endpoints, Catalogo::Products::Show
  ensure
    boot&.shutdown
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

  def test_generated_operation_loads_with_the_project_and_is_not_implemented_yet
    generate(%w[operation catalogo create_product --skip-tests])
    boot = Boto::Boot.new(Boto::Botofile.load(File.join(@dir, "Botofile")), root: @dir, warn_output: StringIO.new)

    boot.load(PROJECT)

    assert_equal Boto::Operation, Catalogo::CreateProduct.superclass
    assert_raises(NotImplementedError) { Catalogo::CreateProduct.call }
    assert_raises(NoMethodError) { Catalogo::CreateProduct.new }
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

  def add_library(name)
    Boto::CLI::Commands::Add.new(["library", name], cwd: @dir, out: @out, err: @err).call
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
