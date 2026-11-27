# boto-rb-gateway

TODO: one paragraph on what this gem adds to Boto.

## Installation

Add it to the Gemfile of the solution (or of the project that uses it):

```ruby
gem "boto-rb-gateway"
```

Then run `bundle install`.

## Plugin

Enable it in the project's `config/app.rb`:

```ruby
Boto.configure do |app|
  app.use :gateway
end
```

## Template

Create a project from it:

```sh
boto add gateway <name>
```

The project is created in `apps/`, as an HTTP project.
