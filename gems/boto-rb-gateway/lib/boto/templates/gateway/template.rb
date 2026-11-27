# frozen_string_literal: true

Boto::Template.define :gateway do |t|
  t.folder "apps"
  t.http true
  t.mounts_refs true
  t.files File.join(__dir__, "files")
  t.summary "Single entry point for the solution's HTTP services (development)"
end
