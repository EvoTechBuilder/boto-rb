# frozen_string_literal: true

class Orders::FrontendLink < Boto::Operation
  def call = app.env.fetch("FRONTEND_URL")
end
