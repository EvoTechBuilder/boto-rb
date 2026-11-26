# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Fewer allocations per request: 76 instead of 88 in the database benchmark scenario and 9 instead of 12 in hello world, with no change to the public API.

### Added

- Monorepo with the boto and boto-cli gems.
- Botofile DSL (`solution`, `project`) with validation of names, templates and references, and cycle detection with the full path.
- `Boto::Endpoint`: one endpoint per class with `get`/`post`/`put`/`patch`/`delete`, typed `param` (String, Integer, Float, `Boto::Boolean`), `status` and `not_found`/`bad_request`/`unprocessable` helpers.
- `Boto::App`: Rack 3 app with endpoint discovery under the project namespace, radix router, JSON bodies up to 1 MB and RFC 9457 problem+json errors (400, 404, 405, 413, 422, 500).
- `Boto::Boot`: loads each project with its own Zeitwerk loader, referenced projects first.
- CLI commands `boto new`, `add` (webapi and library skeletons), `ref`, `graph`, `test` (with `--affected`) and `run` (one Falcon reactor, one port per service).
- Benchmarks against Roda and Sinatra, and CI on Ruby 3.4, 4.0 and head with YJIT on and off.
