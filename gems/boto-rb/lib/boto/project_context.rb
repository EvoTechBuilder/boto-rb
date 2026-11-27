# frozen_string_literal: true

module Boto
  # What `<Project>.app` returns: the project name, the environment it booted with and its own Boto::Env.
  ProjectContext = Data.define(:name, :env_name, :env)
end
