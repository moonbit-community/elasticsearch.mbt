///|
test "generate fixture endpoints from official schema shape" {
  let json = @json.parse(
    (
      #|{
      #|  "types": [
      #|    {
      #|      "kind": "request",
      #|      "name": { "name": "Request", "namespace": "_global.search" },
      #|      "path": [
      #|        {
      #|          "name": "index",
      #|          "required": false,
      #|          "type": {
      #|            "kind": "instance_of",
      #|            "type": { "name": "string", "namespace": "_builtins" }
      #|          }
      #|        }
      #|      ],
      #|      "query": [
      #|        {
      #|          "name": "typed_keys",
      #|          "required": false,
      #|          "type": {
      #|            "kind": "instance_of",
      #|            "type": { "name": "boolean", "namespace": "_builtins" }
      #|          }
      #|        }
      #|      ],
      #|      "body": {
      #|        "kind": "properties",
      #|        "properties": [
      #|          {
      #|            "name": "query",
      #|            "required": false,
      #|            "type": { "kind": "user_defined_value" }
      #|          }
      #|        ]
      #|      }
      #|    },
      #|    {
      #|      "kind": "response",
      #|      "name": { "name": "Response", "namespace": "_global.search" },
      #|      "body": {
      #|        "kind": "properties",
      #|        "properties": [
      #|          {
      #|            "name": "took",
      #|            "required": true,
      #|            "type": {
      #|              "kind": "instance_of",
      #|              "type": { "name": "long", "namespace": "_types" }
      #|            }
      #|          },
      #|          {
      #|            "name": "warning",
      #|            "required": false,
      #|            "type": {
      #|              "kind": "instance_of",
      #|              "type": { "name": "string", "namespace": "_builtins" }
      #|            }
      #|          }
      #|        ]
      #|      }
      #|    }
      #|  ],
      #|  "endpoints": [
      #|    {
      #|      "name": "search",
      #|      "request": { "name": "Request", "namespace": "_global.search" },
      #|      "response": { "name": "Response", "namespace": "_global.search" },
      #|      "requestBodyRequired": false,
      #|      "requestMediaType": ["application/json"],
      #|      "urls": [
      #|        { "methods": ["GET", "POST"], "path": "/_search" },
      #|        { "methods": ["GET", "POST"], "path": "/{index}/_search" }
      #|      ]
      #|    },
      #|    {
      #|      "name": "msearch",
      #|      "requestBodyRequired": true,
      #|      "requestMediaType": ["application/x-ndjson"],
      #|      "urls": [
      #|        { "methods": ["GET", "POST"], "path": "/_msearch" },
      #|        { "methods": ["GET", "POST"], "path": "/{index}/_msearch" }
      #|      ]
      #|    },
      #|    {
      #|      "name": "_internal.hidden",
      #|      "codegenExclude": true,
      #|      "urls": [
      #|        { "methods": ["GET"], "path": "/_internal/hidden" }
      #|      ]
      #|    }
      #|  ]
      #|}
    ),
  )
  let endpoints = parse_schema(json)
  assert_eq(endpoints.length(), 2)
  let root = generate_root(endpoints)
  assert_true(root.contains("pub async fn Client::search("))
  assert_true(root.contains("index? : String"))
  assert_true(root.contains("warning: match obj.get(\"warning\")"))
  assert_true(
    root.contains(
      "Some(value) => Some(@json.from_json(value, path=path.add_key(\"warning\")))",
    ),
  )
  assert_true(root.contains("pub type MsearchBody = Array[Json]"))
  assert_true(root.contains("let body = Ndjson(request.body)"))
  let v9 = generate_v9(endpoints)
  assert_true(v9.contains("pub type SearchRequest = @es.SearchRequest"))
  assert_true(v9.contains("client.msearch(request)"))
}
