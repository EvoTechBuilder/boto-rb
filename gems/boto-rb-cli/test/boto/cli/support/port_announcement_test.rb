# frozen_string_literal: true

require "test_helper"

class Boto::CLI::PortAnnouncementTest < Minitest::Test
  HOST = "localhost"
  GATEWAY_RESULT = Boto::CLI::PortPlan::Result.new(
    ports: { "catalogo" => 4101, "users" => 6001, "borda" => 3000 },
    random: %w[users],
    gateways: { "borda" => %w[catalogo users] }
  )
  PLAIN_RESULT = Boto::CLI::PortPlan::Result.new(
    ports: { "catalogo" => 4101, "users" => 3000 }, random: [], gateways: {}
  )

  def test_gateway_block_lists_services_and_panel_in_development
    expected = [
      "Gateway borda on http://localhost:3000",
      "  catalogo  http://localhost:3000/catalogo   http://localhost:4101",
      "  users     http://localhost:3000/users      http://localhost:6001 (random)",
      "  panel     http://localhost:3000/_boto"
    ]

    assert_equal expected, lines(GATEWAY_RESULT, development: true)
  end

  def test_gateway_block_has_no_panel_outside_development
    lines = lines(GATEWAY_RESULT, development: false)

    assert_equal 3, lines.size
    refute(lines.any? { _1.include?("panel") })
  end

  def test_without_gateways_each_project_is_one_line
    expected = ["  catalogo  http://localhost:4101", "  users  http://localhost:3000"]

    assert_equal expected, lines(PLAIN_RESULT, development: true)
  end

  private

  def lines(result, development:)
    Boto::CLI::PortAnnouncement.new(result, host: HOST, development: development).lines
  end
end
