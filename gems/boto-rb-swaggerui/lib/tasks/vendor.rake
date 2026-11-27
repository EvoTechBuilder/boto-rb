# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "rubygems/package"
require "stringio"
require "zlib"

# Downloads swagger-ui-dist from the npm registry into vendor/swagger-ui.
module SwaggerUiVendor
  HOST = "registry.npmjs.org"
  PACKAGE = "swagger-ui-dist"
  VERSION_PATTERN = /\A\d+\.\d+\.\d+\z/
  FILES = %w[swagger-ui.css swagger-ui-bundle.js LICENSE].freeze
  DIR = File.expand_path("../../vendor/swagger-ui", __dir__)
  MAX_REDIRECTS = 3

  module_function

  def update(version)
    raise ArgumentError, "versão inválida: #{version.inspect}" unless version.match?(VERSION_PATTERN)

    dist = JSON.parse(get(URI("https://#{HOST}/#{PACKAGE}/#{version}"))).fetch("dist")
    tarball = get(URI(dist.fetch("tarball")))
    verify_integrity!(tarball, dist.fetch("integrity"))
    write(extract(tarball), version)
  end

  # Only https to the npm registry is allowed, including on redirects.
  def get(uri, redirects = MAX_REDIRECTS)
    raise "host não permitido: #{uri}" unless uri.scheme == "https" && uri.host == HOST

    response = Net::HTTP.get_response(uri)
    case response
    when Net::HTTPSuccess then response.body
    when Net::HTTPRedirection then follow(uri, response, redirects)
    else raise "HTTP #{response.code} em #{uri}"
    end
  end

  def follow(uri, response, redirects)
    raise "redirects demais em #{uri}" unless redirects.positive?

    get(URI.join(uri, response["location"]), redirects - 1)
  end

  def verify_integrity!(body, integrity)
    expected = "sha512-#{Digest::SHA512.base64digest(body)}"
    raise "integridade divergente: esperado #{integrity}, obtido #{expected}" unless integrity == expected
  end

  def extract(tarball)
    contents = {}
    Zlib::GzipReader.wrap(StringIO.new(tarball)) do |gzip|
      Gem::Package::TarReader.new(gzip).each do |entry|
        name = entry.full_name.delete_prefix("package/")
        contents[name] = entry.read if entry.file? && FILES.include?(name)
      end
    end
    missing = FILES - contents.keys
    raise "faltando no tarball: #{missing.join(", ")}" unless missing.empty?

    contents
  end

  def write(contents, version)
    FileUtils.mkdir_p(DIR)
    contents.each { |name, body| File.binwrite(File.join(DIR, name), body) }
    File.write(File.join(DIR, "VERSION"), "#{version}\n")
  end
end

namespace :vendor do
  desc "Baixa swagger-ui-dist VERSION do npm para vendor/swagger-ui (confere sha512)"
  task :update, [:version] do |_task, args|
    raise ArgumentError, "uso: rake \"vendor:update[VERSION]\"" unless args[:version]

    SwaggerUiVendor.update(args[:version])
  end
end
