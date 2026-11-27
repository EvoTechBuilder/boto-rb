# frozen_string_literal: true

class Orders::Frontend < Boto::Endpoint
  get "/frontend"

  def call = { url: app.env.fetch("FRONTEND_URL") }
end
