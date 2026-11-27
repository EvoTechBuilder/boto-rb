# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `app.use :openapi` (core) serves the OpenAPI document in every environment: `path:` (default `/openapi.json`), `version:` (default `"0.0.0"`) and `auth:` (default `true`, so the project's `:auth` guards it; `auth: false` makes it public). The document is generated once at boot; an endpoint on the same `GET` path fails the boot. Without the plugin, `/openapi.json` still exists only in development.
- New gem `boto-rb-swaggerui`: `app.use :swagger_ui` (`path:`, default `/docs`) serves Swagger UI 5.36.0, vendored in the gem (no CDN, no inline script), for the `:openapi` document. The page follows the `:openapi` guard; the boot fails without `:openapi`, or when the document is guarded by an `:auth` strategy the browser cannot send by itself (anything but `:basic`).
- `app.use :name` finds a plugin from any gem: after `boto-rb-security`, it requires `boto/<name>`. `Boto::INFLECTIONS` keeps plugin names and Zeitwerk constants in sync.
- `:openapi` and `:swagger_ui` in `Boto::Plugin::ORDER`, between `:csrf` and `:auth`.

## [0.10.0] - 2026-11-26

### Changed

- **Breaking:** `webapi` and `microservice` projects live in `apps/`, next to `web` and `spa`; the `services/` folder is gone. A solution whose HTTP project is still in `services/<name>` fails at boot and in every CLI command with the command that fixes it. To migrate, run `git mv services/<name> apps/<name>` for each project.
- `boto new` no longer creates empty `apps/`, `libs/`, `services/` and `workers/` folders; `boto add` creates the folder a project needs.

### Added

- `Boto::Layout.check!(solution, root:)` and `Boto::LegacyLayoutError`.

## [0.9.1] - 2026-11-26

### Fixed

- `boto run` graceful shutdown no longer hangs on Ruby 3.4 or with keep-alive connections: the server tasks are stopped once the requests in flight are done, and a shutdown that starts before the listeners are bound closes them as they come up.

## [0.9.0] - 2026-11-26

Tagged but never published: its CI test job hung on Ruby 3.4 (fixed in 0.9.1).

### Added

- `app.use :health` (core): `GET /health/live` answers 200 while the process serves, and `GET /health/ready` answers 200 or 503 after running the project checks (`checks:`, with `timeout:`) and the checks plugins expose. It runs before every other plugin, so probes need no credentials and pass `:hosts`. Failures are logged and never exposed in the response, and readiness answers 503 once the app drains.
- Plugin hooks `attach(app)`, `drain` and `health_checks`, and `Boto::App#drain!` and `#plugins`.
- `Boto::Redis::RateLimitStore#healthy?` pings Redis, and the `:rate_limit` plugin exposes it as the `rate_limit_store` check.
- `boto run --shutdown-timeout N` (default 25) and `--drain-delay N` (default 0).

### Changed

- `boto run` shuts down gracefully: the first TERM or INT drains the apps (readiness answers 503), keeps serving for the drain delay, stops accepting connections and waits for the requests in flight up to the shutdown timeout, then stops the plugins. A second signal stops at once with exit status 1.
- New `webapi` projects use `app.use :health` instead of a generated `Health` endpoint and schema. Existing projects keep their `/health` endpoint.

### Fixed

- `boto test` says "1 project tested" instead of "1 projects tested".

## [0.8.0] - 2026-11-26

### Added

- `boto -v` (also `--version` and `version`) prints the boto and Ruby versions. `boto help <command>` and `-h`/`--help` after any command print that command's usage, summary and described options without running it. An unknown command suggests a close one (`chek` -> `check`).
- `Boto::Plugin#error_statuses` (empty by default) lets a plugin declare the statuses it can answer, and `Boto::App#plugins_for(endpoint)` lists the plugins that run on an endpoint.
- Plugin lifecycle: `Boto::Plugin#start` and `#stop` (no-ops by default). `Boto::App#start` starts every plugin of the app in the fixed order, including the `:auth` instances built by `authenticate`; a failing start stops the plugins already started and raises `Boto::App::BootError`. `Boto::App#stop` stops them in reverse order and logs failures. Both are idempotent.
- `Boto::Redis::RateLimitStore#close` shuts down the pool built from `url:` (an injected `client:` stays open), and the `:rate_limit` plugin closes its store on stop.
- `Boto::RequestBody.read(env, limit:)` returns the raw request body under the same size limit as JSON parsing (1 MB by default) and raises `Boto::Error::PayloadTooLarge` (413) above it.

### Changed

- The general help (`boto`, `boto -h`, `boto help`) shows the version, the commands in workflow order with aligned columns, the global options and where to find command help. Usage lines start with `Usage:`.
- The OpenAPI document lists every error the framework can answer for an operation: 400 and 413 when the core reads the body, 401 for `:auth` plus 413 for `:signature`, 429 for `:rate_limit` and 503 for a Redis store with `on_error: :deny`. Codes declared with `errors` are not repeated.
- Invalid type constraints fail when the schema is declared: `min` greater than `max`, NaN or infinite bounds, negative or fractional length bounds, repeated `enum` values and `enum` values that break `min`, `max` or `pattern`.
- `Boto::Boot#load` rolls back the loaders it created when `setup` or `eager_load` fails, so the same `Boot` can load again. `Boto::Boot#shutdown` tries every loader, logs each failure to `warn_output` and always clears its state.
- `Boto::Boot#app` returns a started app, and `Boto::Boot#shutdown` stops the apps it built before unloading the project code. Code that builds `Boto::App.new` directly calls `start` and `stop` itself.

### Fixed

- Auth strategies keep deep frozen copies of their settings (keys, credentials, tokens, algorithms, secrets, header and prefix). Changing the caller's objects after boot no longer changes authentication, and `:jwt` no longer freezes the caller's `algorithms` array.
- The `:signature` auth strategy no longer reads an unbounded body: it reads through `Boto::RequestBody.read` and answers 413 above the limit. An input without `rewind` is replaced with the body it read, so the endpoint can still read it.
- The Botofile rejects two projects whose names map to the same Ruby namespace (`foo_bar` and `foo__bar` both give `FooBar`), which would make them share one module and break isolation.
- A schema whose compile failed is no longer reported as compiled: the next `compile!` retries and raises the same error, instead of `serialize` recursing until `SystemStackError`. Field names that shadow public `Object` methods (`object_id`, `send`...), `initialize` or the generated `__boto` methods are rejected. Ruby keywords such as `end` stay valid field names.

## [0.7.3] - 2026-11-26

### Changed

- The CI publishes to RubyGems only after every test job passes, in parallel with the benchmark, which now compares a version tag with the previous one. No code changes from 0.7.2.

## [0.7.2] - 2026-11-26

### Changed

- Releases are published to RubyGems by the `Release` workflow when a `v*` tag is pushed, using trusted publishing. No code changes from 0.7.1.

## [0.7.1] - 2026-11-26

### Fixed

- `boto new` adds Minitest to the generated Gemfile. Without it, `boto test` failed in a new solution with `cannot load such file -- minitest/autorun`, because Minitest is a bundled gem and Bundler only loads gems the Gemfile lists. Existing solutions can add `gem "minitest", "~> 6.0"` to a `:test` group.

## [0.7.0] - 2026-11-26

First release published on RubyGems.

### Added

- Each gem ships the MIT license and links to the source code and changelog.

### Changed

- Gems are published under the `boto-rb` prefix, because the name `boto` is already taken on RubyGems: `boto-rb` (core), `boto-rb-cli`, `boto-rb-security` and `boto-rb-redis`. Require paths (`require "boto"`, `"boto/security"`, `"boto/redis"`), the `Boto` module and the `boto` executable stay the same. Solutions generated by `boto new` declare each gem with its `require:`; update existing Gemfiles to match.
- The isolation check (`boto check` and boot) also reports constants declared at the top level of a project file outside the project's namespace, such as `TOKENS = ...` or `class Helpers` in `config/app.rb`. In dev every project shares one process, so these constants would leak into `Object` and clash between projects. Files under `test/` are not checked for this rule, since each project runs its tests in its own process.

## [0.6.0] - 2026-11-26

### Added

- Project isolation check: a project may only use the namespaces of the projects it references directly. `Boto::Boot` checks each project before loading it and raises `Boto::IsolationError` listing file, line, constant and the `boto ref` command that fixes it. `BOTO_SKIP_ISOLATION=1` skips the boot check with a warning.
- `boto check [project]` reports isolation violations and exits 1 when any is found.

### Changed

- `Boto::Redis::RateLimitStore` uses a pool of 20 connections by default (was 5; connections open on demand) and reuses the fixed part of the counter key, cutting two allocations per request.

## [0.5.0] - 2026-11-26

### Added

- New gem `boto-redis` with `Boto::Redis::RateLimitStore`: a rate limit store shared by every process and instance through Redis, counting with one atomic Lua script per request. It uses a connection pool, a 100 ms timeout, `on_error: :allow` (default, fail-open with one log line per window) or `:deny` (503), and never logs the Redis URL. Load it with `require "boto/redis"` in `config/app.rb`.
- `Boto::Error::ServiceUnavailable` (503), and the rate limit plugin answers errors raised by its store.

### Fixed

- `boto run` no longer serves GET responses from Falcon's built-in HTTP cache, which skipped the app (and so auth and rate limits) on repeated requests.

### Changed

- The rate limit memory store keeps at most `max_keys` keys per window (100,000 by default, configurable with `app.use :rate_limit, max_keys:`) and evicts the oldest keys first, so memory stays bounded under a flood of distinct clients.

## [0.4.0] - 2026-11-26

### Added

- `Boto.configure` in each project's `config/app.rb`, with `app.use :plugin, options`. Plugins are global (run before routing) or per endpoint (compiled per route at boot), in a fixed order: hosts, cors, auth, rate_limit.
- New gem `boto-security` with the `:hosts`, `:cors`, `:auth` and `:rate_limit` plugins. Auth strategies: `basic`, `bearer`, `api_key`, `jwt` (algorithm allowlist, never `none`) and `signature` (HMAC of the raw body with optional timestamp tolerance).
- Endpoint DSL `skip` and `authenticate`, and the `principal` helper.
- 401, 403 and 429 problem responses with `WWW-Authenticate`, `Retry-After` and `RateLimit-*` headers.
- OpenAPI `securitySchemes`, per-operation `security` and 401 responses.
- The `webapi` template enables cors, bearer auth and rate limiting, with a public health endpoint and a development token.
- Boto-only `db_auth` benchmark scenario.

### Changed

- `boto openapi` boots the app in development, so it does not need production secrets.

## [0.3.0] - 2026-11-26

### Added

- HTTP QUERY verb: `query "/path"` declares a safe, idempotent endpoint that reads its input from the body, usually with `body Schema`.
- OpenAPI documents use version 3.2.0 and its `query` operation when the app has QUERY endpoints; other apps keep 3.1.0.

## [0.2.0] - 2026-11-26

### Added

- `Boto::Schema`: declare fields once to validate input into frozen instances and to serialize output through an allowlist of fields. Nested schemas, lists and self-referencing schemas are supported.
- Shared types for params and schema fields: `Date`, `Time` (ISO 8601 with time zone) and lists such as `[Integer]`, besides String, Integer, Float and `Boto::Boolean`, with `min`, `max`, `enum` and anchored `pattern` constraints.
- Endpoint DSL `body`, `returns` (schema or `[schema]`), `summary` and `errors`. Validation errors report the full field path, such as `address.zip` and `tags[2]`.
- `Boto::OpenAPI.generate` builds OpenAPI 3.1 documents; `GET /openapi.json` is served in development only, and `boto openapi <project> [-o FILE]` prints or writes the document.
- Projects load `schemas/`, and the `webapi` template returns a `HealthSchema`.
- Boto-only `db_schema` benchmark scenario that measures the cost of `returns`.

### Changed

- Fewer allocations per request: 76 instead of 88 in the database benchmark scenario and 9 instead of 12 in hello world, with no change to the public API.
- Params are built on the shared types, and the internal `Boto::Params::COERCERS` constant was removed.

## [0.1.0] - 2026-11-26

### Added


- Monorepo with the boto and boto-cli gems.
- Botofile DSL (`solution`, `project`) with validation of names, templates and references, and cycle detection with the full path.
- `Boto::Endpoint`: one endpoint per class with `get`/`post`/`put`/`patch`/`delete`, typed `param` (String, Integer, Float, `Boto::Boolean`), `status` and `not_found`/`bad_request`/`unprocessable` helpers.
- `Boto::App`: Rack 3 app with endpoint discovery under the project namespace, radix router, JSON bodies up to 1 MB and RFC 9457 problem+json errors (400, 404, 405, 413, 422, 500).
- `Boto::Boot`: loads each project with its own Zeitwerk loader, referenced projects first.
- CLI commands `boto new`, `add` (webapi and library skeletons), `ref`, `graph`, `test` (with `--affected`) and `run` (one Falcon reactor, one port per service).
- Benchmarks against Roda and Sinatra, and CI on Ruby 3.4, 4.0 and head with YJIT on and off.
