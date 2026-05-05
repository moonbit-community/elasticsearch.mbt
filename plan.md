# MoonBit Elasticsearch Client v9

## Summary

- Build a native-only MoonBit Elasticsearch client for `moonbit-community/elasticsearch`, backed by `moonbitlang/async/http`.
- Generate the full strongly typed v9 REST API surface from a vendored official Elasticsearch specification.
- Use a MoonBit native codegen tool, not Python/Node, and commit both the spec and generated MoonBit sources.

## Key Changes

- Add dependencies on `moonbitlang/async` and core JSON/base64 packages; set library/codegen packages to native-only.
- Add public handwritten core APIs:
  - `Client`, `ClientConfig`, `Auth`, `ApiCompatibility`, `EsError`, `EsResponse[T]`.
  - `Client::new`, `Client::close`, and low-level `Client::perform`.
  - Auth variants: API key, bearer token, basic auth, and no auth.
- Vendor full official spec under `spec/elasticsearch/v9/`, with source metadata and license notes.
- Add `cmd/codegen` as a MoonBit executable using `@fs.read_file`, `@fs.write_file`, and `@json.parse`.
- Generate:
  - `v9/` package with request/response/body/query types, JSON codecs, enums, aliases, and NDJSON helpers.
  - root generated aliases and `Client` endpoint methods like `search`, `indices_create`, `security_create_api_key`.
- Encode paths, query parameters, media types, API key auth headers, JSON bodies, NDJSON bodies, and error responses centrally.

## Type Strategy

- Generate concrete MoonBit structs/enums for all static spec shapes.
- Preserve spec generics where practical, especially document/source payloads.
- Use `Json` only for intentionally open Elasticsearch shapes such as arbitrary documents, script params, and dynamic keyed maps.
- Codegen fails on unsupported spec constructs instead of silently weakening types.

## Test Plan

- Add codegen golden tests using a small fixture schema.
- Add unit tests for path selection, URL escaping, query encoding, auth headers, media headers, JSON codecs, and error mapping.
- Add native fake-server tests with `@http.Server` for success, error, empty-body, JSON body, and NDJSON endpoints.
- Add integration tests gated by `ES_TEST_URL` and `ES_API_KEY`.
- Final validation: `moon run cmd/codegen -- --check`, `moon check --target native`, `moon test --target native`, `moon info && moon fmt`.

## Assumptions

- Version baseline is Elasticsearch v9, pinned to the latest confirmed release line, currently 9.3.3.
- ES 8 support is best-effort for APIs shared with v9; 9-only generated APIs are not expected to work against ES 8.
- REST compatibility headers are configurable but not enabled by default for the v9 baseline.
- Sources used for planning: official Elasticsearch specification repo, Elastic auth docs, REST compatibility docs, and client compatibility docs.
