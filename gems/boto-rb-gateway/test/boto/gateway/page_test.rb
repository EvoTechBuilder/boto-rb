# frozen_string_literal: true

require "test_helper"

module Boto
  module Gateway
    class PageTest < Minitest::Test
      def test_project_name_comes_from_the_namespace
        assert_equal "borda", Page.project_name("Borda")
        assert_equal "loja_borda", Page.project_name("LojaBorda")
        assert_equal "gateway", Page.project_name("PanelFakes::Gateway")
      end
    end
  end
end
