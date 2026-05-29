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
#cfg(target="native")
async test "v9 wrappers integrate with root client endpoints" {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.add_defer(() => server.close())
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((request, body, conn) => {
        let request_body = body.read_all().text()
        if request.path == "/" {
          conn
          ..send_response(200, "OK")
          .write(
            Json::object({
              "cluster_name": Json::string("wrapper-cluster"),
              "cluster_uuid": Json::string("uuid-v9"),
              "name": Json::string("node-v9"),
              "tagline": Json::string("You Know, for Search"),
              "version": Json::object({ "number": Json::string("9.0.0") }),
            }).stringify(),
          )
        } else if request.path.contains("/_msearch") {
          conn
          ..send_response(200, "OK")
          .write(
            Json::object({
              "path": Json::string(request.path),
              "content_type": Json::string(
                test_header_value(
                  request.headers,
                  "Content-Type",
                  "content-type",
                ),
              ),
              "body": Json::string(request_body),
            }).stringify(),
          )
        } else if request.path.contains("/_search") {
          conn
          ..send_response(200, "OK")
          .write(
            Json::object({
              "path": Json::string(request.path),
              "body": test_json_body_or_text(request_body),
            }).stringify(),
          )
        } else {
          conn
          ..send_response(404, "Not Found")
          .write(
            Json::object({ "error": Json::string(request.path) }).stringify(),
          )
        }
      })
    })
    let client = @es.Client::new(
      @es.ClientConfig::new("http://127.0.0.1:\{server.addr.port()}"),
    )
    defer client.close()
    let info = @v9.info(client, InfoRequest::new())
    @debug.assert_eq(info.body.cluster_uuid, Json::string("uuid-v9"))
    let search = @v9.search(
      client,
      SearchRequest::new(
        index="v9/logs",
        body=SearchBody::new(
          query=Json::object({ "match_all": Json::object({}) }),
        ),
      ),
    )
    assert_true(
      test_json_string_field(search.body, "path").contains("/v9%2Flogs/_search"),
    )
    let msearch = @v9.msearch(
      client,
      MsearchRequest::new(
        [
          Json::object({ "index": Json::string("v9/logs") }),
          Json::object({
            "query": Json::object({ "match_all": Json::object({}) }),
          }),
        ],
        index="v9/logs",
      ),
    )
    assert_true(
      test_json_string_field(msearch.body, "path").contains(
        "/v9%2Flogs/_msearch",
      ),
    )
    assert_eq(
      test_json_string_field(msearch.body, "content_type"),
      "application/x-ndjson",
    )
    assert_true(test_json_string_field(msearch.body, "body").contains("\n"))
  })
}
