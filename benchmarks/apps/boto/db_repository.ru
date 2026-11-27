# frozen_string_literal: true

require "boto"
require "boto/database"
require_relative "../../support/database"

# Igual ao db_schema, mas a leitura passa pelo Boto::Repository (boto-rb-data). Mede o custo do Repository sobre o Sequel.
# Sem o plugin :database: a conexao e registrada direto, como os outros cenarios que usam o DB direto.
module BenchDbRepository
  DB = BenchDatabase.connect
  User = Data.define(:id, :name)

  class UserSchema < Boto::Schema
    field :id, Integer
    field :name, String
  end

  class UserRepository < Boto::Repository
    entity User
    table :users
  end

  class Show < Boto::Endpoint
    get "/users/:id"
    param :id, Integer
    returns UserSchema

    def call(id:) = UserRepository.find(id) || not_found("user not found")
  end
end

Boto::Database::Connections.register(BenchDbRepository, BenchDbRepository::DB)
run Boto::App.new(namespace: BenchDbRepository, env_name: "production", error_output: $stderr)
