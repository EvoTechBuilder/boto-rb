# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# A directory shaped like a gem's lib/ that ships boto/templates/<name>/template.rb files.
class FakeTemplateGem
  attr_reader :root

  def initialize
    @root = File.realpath(Dir.mktmpdir("fake-template-gem"))
  end

  def write(name, source)
    dir = File.join(root, "boto", "templates", name)
    FileUtils.mkdir_p(File.join(dir, "files"))
    path = File.join(dir, "template.rb")
    File.write(path, source)
    path
  end

  # Puts the gem on $LOAD_PATH and forgets the loaded registry, so the next lookup finds it.
  def activate
    $LOAD_PATH.unshift(root)
    Boto::Templates.reset!
  end

  def cleanup
    $LOAD_PATH.delete(root)
    Boto::Templates.reset!
    FileUtils.remove_entry(root)
  end
end
