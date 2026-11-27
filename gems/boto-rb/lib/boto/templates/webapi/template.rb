# frozen_string_literal: true

Boto::Template.define :webapi do |t|
  t.folder "apps"
  t.http true
  t.legacy_services true
  t.summary "REST API with routes, schemas, OpenAPI and JSON errors"
end
