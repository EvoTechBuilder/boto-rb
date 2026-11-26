# frozen_string_literal: true

require "sequel"

module BenchDatabase
  USER_COUNT = 1000

  def self.connect
    db = Sequel.sqlite
    db.create_table(:users) do
      primary_key :id
      String :name, null: false
    end
    db[:users].multi_insert(seed_rows)
    db
  end

  def self.seed_rows
    Array.new(USER_COUNT) { |index| { id: index + 1, name: "user #{index + 1}" } }
  end
end
