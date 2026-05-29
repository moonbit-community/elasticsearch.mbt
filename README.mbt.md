# moonbit-community/elasticsearch

`moonbit-community/elasticsearch` is a native-only MoonBit client for
Elasticsearch v9. It provides a small hand-written HTTP client core plus
generated request, response, and endpoint wrappers derived from the vendored
official Elasticsearch v9 schema.

The package is designed for MoonBit programs that run on the `native` target and
need typed access to Elasticsearch APIs while still keeping a JSON escape hatch
for the parts of the Elasticsearch schema that are too broad or dynamic to model
precisely.

## Status

- Package version: `0.1.0`
- Supported target: `native`
- Elasticsearch schema baseline: v9.3.3
- License: Apache-2.0
- Generated endpoint count: 587
- Main generated sources:
  - `generated_endpoints.mbt`
  - `v9/generated.mbt`

This is an early client. The public API is useful, but consumers should expect
schema-driven type refinements as the generator improves.

## Package Layout

```text
.
|-- client.mbt                 # Client lifecycle, headers, HTTP execution, JSON decoding
|-- encoding.mbt               # URL path/query rendering and NDJSON encoding
|-- types.mbt                  # Public core types: ClientConfig, Auth, EsRequest, EsResponse
|-- generated_endpoints.mbt    # Root-package generated Client endpoint methods
|-- v9/
|   |-- generated.mbt          # v9 package function wrappers and type aliases
|   `-- moon.pkg
|-- cmd/codegen/
|   `-- main.mbt               # Schema-to-MoonBit generator
`-- spec/elasticsearch/v9/
    |-- schema.json            # Vendored official Elasticsearch API schema
    |-- METADATA.md
    |-- LICENSE
    |-- validation-errors.json
    |-- dangling-types.csv
    `-- fixture.json
```

`README.md` is a symlink to `README.mbt.md`, which is the module readme declared
in `moon.mod`.

## Installation

This module targets native MoonBit only. In a consuming package, import the root
client package from `moon.pkg` and set the package target accordingly:

```moonbit nocheck
import {
  "moonbit-community/elasticsearch" @es,
  "moonbitlang/core/json",
}

supported_targets = "+native"
```

If you prefer the versioned function-wrapper package, also import:

```moonbit nocheck
import {
  "moonbit-community/elasticsearch/v9" @esv9,
}
```

The root package exposes endpoint methods on `Client`, such as
`client.search(...)`. The `v9` package exposes thin functions, such as
`@esv9.search(client, ...)`, and aliases the same generated request and response
types.

## Quick Start

Create a client with the convenience constructor:

```moonbit nocheck
///|
async fn main {
  let client = @es.new(
    "http://localhost:9200",
    auth=@es.Auth::basic(username="elastic", password="secret"),
    headers={ "X-Client": "my-moonbit-app" },
  )
  defer client.close()

  let info = client.info(@es.InfoRequest::new())
  println(info.body.tagline)
}
```

For fuller control, build a `ClientConfig` explicitly:

```moonbit nocheck
///|
async fn main {
  let config = @es.ClientConfig::new(
    "http://localhost:9200",
    auth=@es.Auth::api_key(id="elastic", api_key="secret"),
    compatibility=@es.ApiCompatibility::CompatibleWith8,
    headers={ "X-Client": "my-moonbit-app" },
  )

  let client = @es.Client::new(config)
  defer client.close()

  let response = client.info(@es.InfoRequest::new())
  println(response.status.to_string())
}
```

## Authentication

`Auth` supports the common Elasticsearch authorization modes:

- `NoAuth`: send no `Authorization` header.
- `Auth::api_key(id~, api_key~)`: build an Elasticsearch API key header from an
  ID and key pair.
- `ApiKey(value)`: use a pre-encoded API key value directly.
- `BearerToken(token)`: send a bearer token.
- `Auth::basic(username~, password~)`: build a Basic authentication header.

Authentication is configured once on `ClientConfig` and applied to every request
made by that client. Per-request headers can still override or add headers when
using the lower-level `EsRequest` path.

## Compatibility Headers

`ApiCompatibility` controls the default `Accept` header:

- `Default`: `application/json`
- `CompatibleWith8`: `application/vnd.elasticsearch+json; compatible-with=8`

Request bodies set their own `Content-Type` based on body kind:

- `JsonBody`: `application/json`
- `TextBody`: `text/plain`
- `BinaryBody`: `application/octet-stream`
- `Ndjson`: `application/x-ndjson`

Generated bulk-style endpoints use `Ndjson` automatically when the schema marks
the endpoint as `application/x-ndjson`.

## Calling Generated Endpoints

Each generated endpoint follows the same shape:

- `<Endpoint>Query`: optional query-string fields with `to_pairs()`.
- `<Endpoint>Body`: JSON, NDJSON, text, or a generated body struct when the
  endpoint accepts a body.
- `<Endpoint>Request`: path params, query params, and body.
- `<Endpoint>Response`: either a generated struct or `Json`.
- `Client::<endpoint>(request)`: performs the HTTP call and decodes the response.

Search example:

```moonbit nocheck
///|
async fn search_logs(client : @es.Client) -> Unit {
  let response = client.search(
    @es.SearchRequest::new(
      index="logs-2026",
      query=@es.SearchQuery::new(q="status:200", typed_keys=true, stats=[
        "latency", "errors",
      ]),
      body=@es.SearchBody::new(
        query=Json::object({ "match_all": Json::object({}) }),
        size=10,
      ),
    ),
  )

  println(response.status.to_string())
  println(response.body.stringify())
}
```

Indexing a document:

```moonbit nocheck
///|
async fn index_document(client : @es.Client) -> Unit {
  let document = Json::object({
    "message": Json::string("hello from MoonBit"),
    "service": Json::string("example"),
  })

  let response = client.index(
    @es.IndexRequest::new(
      "logs-2026",
      document,
      id="doc-1",
      query=@es.IndexQuery::new(refresh="wait_for"),
    ),
  )

  println(response.body.stringify())
}
```

Bulk requests are encoded as newline-delimited JSON and always terminate with a
newline:

```moonbit nocheck
///|
async fn bulk_index(client : @es.Client) -> Unit {
  let response = client.bulk(
    @es.BulkRequest::new(
      [
        Json::object({ "index": Json::object({ "_id": Json::string("1") }) }),
        Json::object({ "message": Json::string("first document") }),
      ],
      index="logs-2026",
      query=@es.BulkQuery::new(refresh="wait_for"),
    ),
  )

  println(response.body.errors.to_string())
}
```

## Versioned v9 Package

The root package owns the concrete `Client` and generated endpoint methods. The
`v9` package provides an alternate function-style API that is convenient when you
want versioned imports in application code:

```moonbit nocheck
///|
async fn call_v9(client : @es.Client) -> Unit {
  let info = @esv9.info(client, @esv9.InfoRequest::new())
  println(info.body.tagline)

  let search = @esv9.search(
    client,
    @esv9.SearchRequest::new(
      index="logs-2026",
      body=@esv9.SearchBody::new(
        query=Json::object({ "match_all": Json::object({}) }),
      ),
    ),
  )
  println(search.body.stringify())
}
```

The `v9` request, response, query, and body names are aliases to the root
generated types, so both APIs share the same runtime behavior.

## Raw Requests

Use `perform_json` when an endpoint is not generated yet or when you want full
control over the HTTP request:

```moonbit nocheck
///|
async fn raw_request(client : @es.Client) -> Unit {
  let response = client.perform_json(
    @es.EsRequest::new(@es.HttpMethod::Get, "/_cluster/health", query=[
      ("pretty", "true"),
    ]),
  )

  println(response.body.stringify())
}
```

Use `perform` when you have a response type that implements `FromJson`:

```moonbit nocheck
///|
async fn typed_request(client : @es.Client) -> Unit {
  let response : @es.EsResponse[@es.InfoResponse] = client.perform(
    @es.EsRequest::new(@es.HttpMethod::Get, "/"),
  )
  println(response.body.tagline)
}
```

## Error Handling

Client operations raise `EsError`:

- `ClosedClient`: the request was attempted after `client.close()`.
- `Request(String)`: path selection or request construction failed.
- `Decode(String)`: response decoding failed.
- `Http(status~, reason~, body~)`: Elasticsearch returned a non-2xx status.

HTTP error bodies are parsed as JSON when possible. Empty successful responses
decode to `Json::null()`, and non-JSON successful responses fall back to
`Json::string(text)` when using `perform_json`.

## Encoding Helpers

The root package also exposes helpers used by generated endpoints:

- `percent_encode(value)`: percent-encode a path or query component.
- `encode_query(pairs)`: render query pairs as a query string.
- `append_query(path, pairs)`: append a query string only when pairs exist.
- `render_path_template(template, params)`: bind and encode path parameters.
- `select_path(variants, params)`: choose the most specific path variant whose
  required parameters are present.
- `encode_ndjson(items)`: render JSON items as newline-delimited JSON.

These are public so tests, custom endpoints, and advanced integrations can share
the exact same behavior as generated endpoints.

## Code Generation

The generator reads `spec/elasticsearch/v9/schema.json` and writes:

- `generated_endpoints.mbt`: root-package request, response, and `Client`
  endpoint method definitions.
- `v9/generated.mbt`: aliases and function wrappers for the versioned package.

Regenerate sources:

```bash
moon run cmd/codegen --target native
```

Check whether committed generated files are stale:

```bash
moon run cmd/codegen --target native -- --check
```

Useful generator options:

```text
--check              Compare generated output with existing files.
--input FILE         Read a different schema file.
--root-output FILE   Write root generated endpoints to FILE.
--v9-output FILE     Write v9 wrappers to FILE.
--help               Print generator usage.
```

Do not edit `generated_endpoints.mbt` or `v9/generated.mbt` by hand. Change the
generator or schema input, regenerate, and review the diff.

## Testing

Run the main validation loop:

```bash
moon check --target native
moon test --target native
```

Before handing off changes, update generated interface files and format:

```bash
moon info
moon fmt
```

Integration tests include local fake HTTP servers. There is also an optional
live Elasticsearch smoke test guarded by environment variables:

```bash
ES_TEST_URL=http://localhost:9200 ES_API_KEY=... moon test --target native
```

The live test is skipped when either environment variable is absent.

## Development Notes

- Keep hand-written client behavior in `client.mbt`, `types.mbt`, and
  `encoding.mbt`.
- Keep generated behavior in the generator under `cmd/codegen`.
- Keep vendored schema metadata in `spec/elasticsearch/v9/METADATA.md` current
  when replacing the upstream schema.
- Prefer focused tests for hand-written behavior and generator fixtures for
  schema translation rules.
- Run `moon run cmd/codegen --target native -- --check` in CI or before release
  to catch stale generated sources.

## Current Boundaries

- Only the `native` target is supported because the client depends on
  `moonbitlang/async/http`.
- Some schema constructs intentionally map to `Json` to preserve endpoint
  coverage while avoiding misleading partial models.
- Generated endpoint method names are derived from Elasticsearch endpoint names
  by replacing dots and dashes with underscores.
- The client currently performs JSON-oriented response decoding. Use
  `perform_json` and inspect `EsResponse[Json]` for endpoints with dynamic or
  loosely modeled responses.
