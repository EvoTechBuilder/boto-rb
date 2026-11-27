# frozen_string_literal: true

require "test_helper"

class Boto::ProjectContextTest < Minitest::Test
  def test_context_is_frozen_and_exposes_its_fields
    env = Boto::Env.new({ "FRONTEND_URL" => "https://loja.test" })

    context = Boto::ProjectContext.new(name: "orders", env_name: "test", env: env)

    assert context.frozen?
    assert_equal ["orders", "test", env], [context.name, context.env_name, context.env]
  end
end
