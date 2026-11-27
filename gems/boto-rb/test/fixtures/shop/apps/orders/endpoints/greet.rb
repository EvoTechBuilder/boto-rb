# frozen_string_literal: true

class Orders::Greet < Boto::Endpoint
  get "/greet/:name"
  param :name, String
  returns Orders::GreetingSchema
  def call(name:) = { message: Domain::Greeting.call(name) }
end
