# frozen_string_literal: true

Boto::Template.define :microservice do |t|
  t.folder "apps"
  t.http true
  t.legacy_services true
end
