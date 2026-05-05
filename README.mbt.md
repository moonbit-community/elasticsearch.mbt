# moonbit-community/elasticsearch

Native-only MoonBit client for Elasticsearch v9.

The root package exposes `Client`, `ClientConfig`, auth helpers, request/response
types, path/query/NDJSON encoding, and generated endpoint wrappers backed by
the vendored official v9 schema in `spec/elasticsearch/v9/schema.json`.

The `cmd/codegen` package is a MoonBit executable that regenerates
`generated_endpoints.mbt` and `v9/generated.mbt`.

```bash
moon run cmd/codegen --target native -- --check
moon check --target native
moon test --target native
```
