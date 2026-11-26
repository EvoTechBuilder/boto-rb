# frozen_string_literal: true

class Orders::Customers::Show < Boto::Endpoint
  get "/customers/:name"
  param :name, String
  def call(name:) = { name: Domain::Customer.new(name:).name }
end
