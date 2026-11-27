# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# A directory shaped like a gem's lib/ that declares templates under boto/templates/<name>/template.rb.
class FakeTemplateGem
  attr_reader :root

  def initialize
    @root = File.realpath(Dir.mktmpdir("fake-template-gem"))
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

  def declare(name, http:, files: own_files_dir(name), mounts_refs: false)
    write_declaration(name, <<~RUBY)
      Boto::Template.define :#{name} do |t|
        t.folder "apps"
        t.http #{http}
        t.mounts_refs #{mounts_refs}
        t.files #{files.inspect}
      end
    RUBY
  end

  def write_declaration(name, source)
    dir = template_dir(name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "template.rb"), source)
  end

  def write_file(name, relative, content)
    path = File.join(own_files_dir(name), relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  private

  def template_dir(name) = File.join(root, "boto", "templates", name)

  def own_files_dir(name) = File.join(template_dir(name), "files")
end
