# boto-rb-gateway

Single entry point for a Boto solution in development: the `gateway` template
mounts the solution's HTTP services in one process, each under `/<project>`,
and serves the `/_boto` panel.

## Installation

```ruby
# Gemfile of the solution
gem "boto-rb-gateway"
```

```bash
bundle install
boto add gateway borda --refs catalogo,users
boto run
```

## Plugin

```ruby
# apps/borda/config/app.rb
Boto.configure do |app|
  app.use :health
  app.use :gateway, prefixes: { "users" => "/contas" }, panel: true
end
```

- `prefixes:` overrides the default `/<project>` prefix of a service.
- `panel:` turns `/_boto` on or off (default: on in development only).
- The gateway refuses to boot in `production`; there, route with your ingress.

## Panel

`GET /_boto` lists each service with its prefix, port, health (probed in the
same process), routes, OpenAPI and Swagger links and its env variables, with
sensitive values masked. `GET /_boto/services.json` has the same data.

## License

MIT.
