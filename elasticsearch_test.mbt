///|
fn test_header_value(
  headers : Map[String, String],
  canonical : String,
  lowercase : String,
) -> String {
  headers.get_or_default(canonical, headers.get_or_default(lowercase, ""))
}

///|
fn test_json_body_or_text(text : String) -> Json {
  if text.is_empty() {
    Json::null()
  } else {
    @json.parse(text) catch {
      _ => Json::string(text)
    }
  }
}

///|
fn test_json_string_field(json : Json, key : String) -> String raise {
  guard json is Object(obj) && obj.get(key) is Some(String(value)) else {
    fail("expected string field `\{key}`")
  }
  value
}

///|
fn test_json_field(json : Json, key : String) -> Json raise {
  guard json is Object(obj) && obj.get(key) is Some(value) else {
    fail("expected JSON field `\{key}`")
  }
  value
}

///|
#cfg(target="native")
async test "generated endpoints integrate request rendering http and decoding" {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.add_defer(() => server.close())
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((request, body, conn) => {
        let request_body = body.read_all().text()
        let echo = Json::object({
          "path": Json::string(request.path),
          "accept": Json::string(
            test_header_value(request.headers, "Accept", "accept"),
          ),
          "authorization": Json::string(
            test_header_value(request.headers, "Authorization", "authorization"),
          ),
          "content_type": Json::string(
            test_header_value(request.headers, "Content-Type", "content-type"),
          ),
          "client_header": Json::string(
            test_header_value(request.headers, "X-Client", "x-client"),
          ),
          "body": test_json_body_or_text(request_body),
        })
        if request.path == "/" {
          conn
          ..send_response(200, "OK")
          .write(
            Json::object({
              "cluster_name": Json::string("test-cluster"),
              "cluster_uuid": Json::string("uuid-1"),
              "name": Json::string("node-1"),
              "tagline": Json::string("You Know, for Search"),
              "version": Json::object({ "number": Json::string("9.0.0") }),
            }).stringify(),
          )
        } else if request.path.contains("/_count") {
          conn
          ..send_response(200, "OK")
          .write(
            Json::object({
              "count": Json::number(42),
              "_shards": Json::object({ "successful": Json::number(1) }),
            }).stringify(),
          )
        } else if request.path.contains("/_bulk") {
          let content_type = test_header_value(
            request.headers,
            "Content-Type",
            "content-type",
          )
          if content_type == "application/x-ndjson" &&
            request_body.contains("\n") {
            conn
            ..send_response(200, "OK")
            .write(
              Json::object({
                "errors": Json::boolean(false),
                "items": Json::array([
                  Json::object({
                    "index": Json::object({ "_id": Json::string("1") }),
                  }),
                ]),
                "took": Json::number(3),
                "ingest_took": Json::number(1),
              }).stringify(),
            )
          } else {
            conn
            ..send_response(415, "Unsupported Media Type")
            .write(
              Json::object({ "error": Json::string("bad bulk") }).stringify(),
            )
          }
        } else if request.path.contains("/_search") ||
          request.path.contains("/_doc") {
          conn..send_response(200, "OK").write(echo.stringify())
        } else {
          conn
          ..send_response(404, "Not Found")
          .write(
            Json::object({ "error": Json::string(request.path) }).stringify(),
          )
        }
      })
    })
    let client = @elasticsearch.Client::new(
      @elasticsearch.ClientConfig::new(
        "http://127.0.0.1:\{server.addr.port()}",
        auth=@elasticsearch.Auth::api_key(id="elastic", api_key="secret"),
        compatibility=CompatibleWith8,
        headers={ "X-Client": "integration" },
      ),
    )
    defer client.close()
    let info = client.info(InfoRequest::new())
    assert_eq(info.status, 200)
    assert_eq(info.body.tagline, "You Know, for Search")
    assert_true(
      info.body.version == Json::object({ "number": Json::string("9.0.0") }),
    )
    let search = client.search(
      SearchRequest::new(
        index="logs/2026",
        query=SearchQuery::new(
          q="status:200",
          stats=["latency", "errors"],
          typed_keys=true,
        ),
        body=SearchBody::new(
          query=Json::object({ "match_all": Json::object({}) }),
          size=2,
        ),
      ),
    )
    let search_path = test_json_string_field(search.body, "path")
    assert_true(search_path.contains("/logs%2F2026/_search?"))
    assert_true(search_path.contains("q=status%3A200"))
    assert_true(search_path.contains("stats=latency%2Cerrors"))
    assert_true(search_path.contains("typed_keys=true"))
    assert_eq(
      test_json_string_field(search.body, "accept"),
      "application/vnd.elasticsearch+json; compatible-with=8",
    )
    assert_eq(
      test_json_string_field(search.body, "authorization"),
      "ApiKey ZWxhc3RpYzpzZWNyZXQ=",
    )
    assert_eq(
      test_json_string_field(search.body, "content_type"),
      "application/json",
    )
    assert_eq(
      test_json_string_field(search.body, "client_header"),
      "integration",
    )
    assert_true(
      test_json_field(search.body, "body") ==
      Json::object({
        "query": Json::object({ "match_all": Json::object({}) }),
        "size": Json::number(2),
      }),
    )
    let count = client.count(
      CountRequest::new(
        index="logs/2026",
        query=CountQuery::new(q="status:200", terminate_after=10),
        body=CountBody::new(
          query=Json::object({
            "term": Json::object({ "status": Json::number(200) }),
          }),
        ),
      ),
    )
    assert_eq(count.body.count, 42)
    assert_true(
      count.body._shards == Json::object({ "successful": Json::number(1) }),
    )
    let indexed = client.index(
      IndexRequest::new(
        "logs/2026",
        Json::object({ "message": Json::string("hello") }),
        id="id/1",
        query=IndexQuery::new(refresh="wait_for", require_alias=false),
      ),
    )
    let index_path = test_json_string_field(indexed.body, "path")
    assert_true(index_path.contains("/logs%2F2026/_doc/id%2F1?"))
    assert_true(index_path.contains("refresh=wait_for"))
    assert_true(index_path.contains("require_alias=false"))
    assert_true(
      test_json_field(indexed.body, "body") ==
      Json::object({ "message": Json::string("hello") }),
    )
    let bulk = client.bulk(
      BulkRequest::new(
        [
          Json::object({ "index": Json::object({ "_id": Json::string("1") }) }),
          Json::object({ "message": Json::string("hello") }),
        ],
        index="logs/2026",
        query=BulkQuery::new(refresh="wait_for"),
      ),
    )
    assert_eq(bulk.body.errors, false)
    assert_eq(bulk.body.took, 3)
    assert_true(bulk.body.ingest_took == Some(1))
    assert_eq(bulk.body.items.length(), 1)
  })
}
