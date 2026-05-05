///|
test "percent encode path and query values" {
  assert_eq(percent_encode("a b/中文"), "a%20b%2F%E4%B8%AD%E6%96%87")
  assert_eq(
    encode_query([("q", "status:200"), ("index", "logs/2026")]),
    "q=status%3A200&index=logs%2F2026",
  )
}

///|
test "path template selection encodes path parameters" {
  let params : Map[String, String] = { "index": "logs/2026" }
  let path = select_path(
    [
      PathVariant::new("/{index}/_search", ["index"]),
      PathVariant::new("/_search", []),
    ],
    params,
  )
  assert_eq(path, "/logs%2F2026/_search")
}

///|
test "headers include auth compatibility and body media type" {
  let config = ClientConfig::new(
    "http://localhost:9200",
    auth=Auth::basic(username="elastic", password="secret"),
    compatibility=CompatibleWith8,
  )
  let request = EsRequest::new(
    Post,
    "/_search",
    body=JsonBody(Json::object({})),
  )
  let headers = config.request_headers(request)
  assert_eq(headers["Authorization"], "Basic ZWxhc3RpYzpzZWNyZXQ=")
  assert_eq(
    headers["Accept"],
    "application/vnd.elasticsearch+json; compatible-with=8",
  )
  assert_eq(headers["Content-Type"], "application/json")
}

///|
test "ndjson encoding always terminates with newline" {
  let lines = encode_ndjson([Json::object({ "index": Json::string("logs") })])
  assert_eq(lines, "{\"index\":\"logs\"}\n")
}

///|
#cfg(target="native")
async test "perform_json handles fake server success empty and error responses" {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.add_defer(() => server.close())
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((request, body, conn) => {
        let request_body = body.read_all().text()
        if request.path.contains("/error") {
          conn..send_response(400, "Bad Request").write("{\"error\":\"bad\"}")
        } else if request.path.contains("/ndjson") {
          let content_type = request.headers.get_or_default(
            "Content-Type",
            request.headers.get_or_default("content-type", ""),
          )
          conn
          ..send_response(200, "OK")
          .write(
            Json::object({
              "body": Json::string(request_body),
              "content_type": Json::string(content_type),
            }).stringify(),
          )
        } else if request.path.contains("/empty") {
          conn.send_response(204, "No Content")
        } else {
          conn..send_response(200, "OK").write("{\"ok\":true}")
        }
      })
    })
    let client = Client::new(
      ClientConfig::new("http://127.0.0.1:\{server.addr.port()}"),
    )
    defer client.close()
    let ok = client.perform_json(EsRequest::new(Get, "/ok"))
    assert_eq(ok.status, 200)
    assert_true(ok.body == Json::object({ "ok": Json::boolean(true) }))
    let empty = client.perform_json(EsRequest::new(Get, "/empty"))
    assert_eq(empty.status, 204)
    assert_true(empty.body == Json::null())
    let failure : Result[EsResponse[Json], Error] = try? client.perform_json(
      EsRequest::new(Get, "/error"),
    )
    guard failure is Err(EsError::Http(status~, reason~, body~)) else {
      fail("expected Elasticsearch HTTP error")
    }
    assert_eq(status, 400)
    assert_eq(reason, "Bad Request")
    assert_true(body == Json::object({ "error": Json::string("bad") }))
    let ndjson = client.perform_json(
      EsRequest::new(
        Post,
        "/ndjson",
        body=Ndjson([Json::object({ "index": Json::string("logs") })]),
      ),
    )
    assert_eq(ndjson.status, 200)
    assert_true(
      ndjson.body ==
      Json::object({
        "body": Json::string("{\"index\":\"logs\"}\n"),
        "content_type": Json::string("application/x-ndjson"),
      }),
    )
  })
}

///|
#cfg(target="native")
async test "integration Elasticsearch root endpoint when env is configured" {
  match (@env.get_env_var("ES_TEST_URL"), @env.get_env_var("ES_API_KEY")) {
    (Some(url), Some(api_key)) => {
      let client = Client::new(ClientConfig::new(url, auth=ApiKey(api_key)))
      defer client.close()
      let response = client.perform_json(EsRequest::new(Get, "/"))
      assert_true(response.status >= 200 && response.status < 300)
    }
    _ => ()
  }
}
