# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"

# A plugin gem required by app.use can define a base class the project code inherits from (boto-rb-data defines
# Boto::Repository), so the configuration must be read before the project code is eager loaded.
class Boto::BootLoadOrderTest < Minitest::Test
  PLUGIN_SOURCE = <<~RUBY
    # frozen_string_literal: true

    class LoadOrderProbeBase; end

    module Boto
      module Plugins
        class LoadOrderProbe < Boto::Plugin
          def start = nil
        end
      end
    end
  RUBY

  def setup
    @root = Dir.mktmpdir("boto-load-order")
    @lib = File.join(@root, "lib")
    write("lib/boto/load_order_probe.rb", PLUGIN_SOURCE)
    write("Botofile", %(solution "shop"\nproject "ordering", template: :webapi\n))
    write("apps/ordering/config/app.rb", "Boto.configure { |app| app.use :load_order_probe }\n")
    write("apps/ordering/models/thing.rb", "class Ordering::Thing < LoadOrderProbeBase; end\n")
    $LOAD_PATH.unshift(@lib)
  end

  def teardown
    @boot&.shutdown
    $LOAD_PATH.delete(@lib)
    FileUtils.remove_entry(@root)
  end

  def test_project_code_can_inherit_from_a_class_of_a_plugin_gem
    @boot = Boto::Boot.new(Boto::Botofile.load(File.join(@root, "Botofile")), root: @root, env: {},
                                                                                 warn_output: StringIO.new)
    @boot.app("ordering", env_name: "test")

    assert_operator Ordering::Thing, :<, LoadOrderProbeBase
  end

  private

  def write(path, content)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end
end
