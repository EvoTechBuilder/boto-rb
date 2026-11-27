# frozen_string_literal: true

Boto::Template.define :web do |t|
  t.folder "apps"
  t.http true
end
