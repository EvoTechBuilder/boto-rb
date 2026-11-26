# frozen_string_literal: true

require "test_helper"

module Boto
  class RouterTest < Minitest::Test
    def setup
      @router = Router.new
    end

    def test_add_and_compile_return_self
      assert_same @router, @router.add("GET", "/", :root)
      assert_same @router, @router.compile
    end

    def test_matches_root
      @router.add("GET", "/", :root).compile

      match = @router.match("GET", "/")

      assert_equal :root, match.target
      assert_same Router::EMPTY_PARAMS, match.params
    end

    def test_matches_static_path
      @router.add("GET", "/health", :health)

      assert_equal :health, @router.match("GET", "/health").target
    end

    def test_matches_dynamic_segment
      @router.add("GET", "/users/:id", :show)

      match = @router.match("GET", "/users/42")

      assert_equal :show, match.target
      assert_equal({ id: "42" }, match.params)
    end

    def test_matches_mixed_static_and_dynamic_segments
      @router.add("GET", "/users/:id/posts/:post_id", :post)

      match = @router.match("GET", "/users/1/posts/9")

      assert_equal({ id: "1", post_id: "9" }, match.params)
    end

    def test_ignores_trailing_slash
      @router.add("GET", "/users/", :index)

      assert_equal :index, @router.match("GET", "/users").target
      assert_equal :index, @router.match("GET", "/users/").target
    end

    def test_static_segment_wins_over_dynamic
      @router.add("GET", "/users/new", :new)
      @router.add("GET", "/users/:id", :show)

      assert_equal :new, @router.match("GET", "/users/new").target
      assert_equal({ id: "5" }, @router.match("GET", "/users/5").params)
    end

    def test_backtracks_from_static_branch_to_dynamic_branch
      @router.add("GET", "/a/b/c", :abc)
      @router.add("GET", "/a/:x/d", :xd)

      match = @router.match("GET", "/a/b/d")

      assert_equal :xd, match.target
      assert_equal({ x: "b" }, match.params)
      assert_equal :abc, @router.match("GET", "/a/b/c").target
    end

    def test_routes_with_different_param_names_share_dynamic_node
      @router.add("GET", "/users/:id", :show)
      @router.add("GET", "/users/:user_id/posts", :posts)

      assert_equal({ id: "3" }, @router.match("GET", "/users/3").params)
      assert_equal({ user_id: "3" }, @router.match("GET", "/users/3/posts").params)
    end

    def test_distinguishes_verbs_on_same_path
      @router.add("GET", "/x", :get)
      @router.add("POST", "/x", :post)

      assert_equal :get, @router.match("GET", "/x").target
      assert_equal :post, @router.match("POST", "/x").target
    end

    def test_returns_nil_for_unknown_verb
      @router.add("GET", "/x", :get)

      assert_nil @router.match("DELETE", "/x")
    end

    def test_returns_nil_for_unknown_path
      @router.add("GET", "/x", :get)

      assert_nil @router.match("GET", "/nope")
    end

    def test_backtracks_to_dynamic_branch_when_verb_only_exists_there
      @router.add("GET", "/a/b", :static_get)
      @router.add("POST", "/a/:x", :dynamic_post)

      match = @router.match("POST", "/a/b")

      assert_equal :dynamic_post, match.target
      assert_equal({ x: "b" }, match.params)
    end

    def test_head_falls_back_to_get
      @router.add("GET", "/x", :get)

      assert_equal :get, @router.match("HEAD", "/x").target
    end

    def test_explicit_head_has_priority_over_get
      @router.add("GET", "/x", :get)
      @router.add("HEAD", "/x", :head)

      assert_equal :head, @router.match("HEAD", "/x").target
    end

    def test_allowed_verbs_lists_matching_verbs_sorted_with_head
      @router.add("GET", "/users", :index)
      @router.add("POST", "/users", :create)

      assert_equal %w[GET HEAD POST], @router.allowed_verbs("/users")
    end

    def test_allowed_verbs_is_empty_for_unknown_path
      @router.add("GET", "/users", :index)

      assert_equal [], @router.allowed_verbs("/nope")
    end

    def test_decodes_dynamic_values
      @router.add("GET", "/files/:name", :file)

      assert_equal({ name: "a b" }, @router.match("GET", "/files/a%20b").params)
    end

    def test_duplicate_verb_and_shape_raises
      @router.add("GET", "/users/:id", :show)

      error = assert_raises(Router::DuplicateRouteError) do
        @router.add("GET", "/users/:user_id", :other)
      end

      assert_includes error.message, "GET"
      assert_includes error.message, "/users/:user_id"
    end

    def test_duplicate_static_route_raises
      @router.add("GET", "/x", :x)

      assert_raises(Router::DuplicateRouteError) { @router.add("GET", "/x", :y) }
    end

    def test_add_after_compile_raises_frozen_error
      @router.add("GET", "/x", :x).compile

      assert_raises(FrozenError) { @router.add("GET", "/y", :y) }
    end

    def test_compiled_routes_without_params_share_empty_params
      @router.add("GET", "/", :root).add("GET", "/x", :x).compile

      assert_same Router::EMPTY_PARAMS, @router.match("GET", "/").params
      assert_same Router::EMPTY_PARAMS, @router.match("GET", "/x").params
    end

    def test_ignores_duplicate_and_trailing_slashes
      @router.add("GET", "/users/:id", :show).compile

      assert_equal({ id: "42" }, @router.match("GET", "//users//42").params)
      assert_equal({ id: "42" }, @router.match("GET", "/users/42/").params)
    end

    def test_keeps_plain_dynamic_values_and_decodes_percent_escapes
      @router.add("GET", "/files/:name", :file).compile

      assert_equal({ name: "plain" }, @router.match("GET", "/files/plain").params)
      assert_equal({ name: "a b" }, @router.match("GET", "/files/a%20b").params)
    end

    def test_match_allocates_a_bounded_number_of_objects
      @router.add("GET", "/users/:id", :show).compile
      50.times { @router.match("GET", "/users/42") }

      # The first GC.stat window also counts one object of its own; a dry run absorbs it.
      allocations_during { @router.match("GET", "/users/42") }

      # segments array, 2 segment strings, values array, params Hash and the Match.
      assert_operator allocations_during { @router.match("GET", "/users/42") }, :<=, 6
    end

    private

    def allocations_during
      before = GC.stat(:total_allocated_objects)
      yield
      GC.stat(:total_allocated_objects) - before
    end
  end
end
