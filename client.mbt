///|
pub fn ApiCompatibility::media_type(self : ApiCompatibility) -> String {
  match self {
    Default => "application/json"
    CompatibleWith8 => "application/vnd.elasticsearch+json; compatible-with=8"
  }
}

///|
fn Auth::authorization_header(self : Auth) -> String? {
  match self {
    NoAuth => None
    ApiKey(value) => Some("ApiKey \{value}")
    BearerToken(token) => Some("Bearer \{token}")
    Basic(username, password) => {
      let raw = "\{username}:\{password}"
      Some("Basic \{@base64.encode(@utf8.encode(raw))}")
    }
  }
}

///|
fn HttpMethod::to_http_method(self : HttpMethod) -> @http.RequestMethod {
  match self {
    Get => @http.RequestMethod::Get
    Head => @http.RequestMethod::Head
    Post => @http.RequestMethod::Post
    Put => @http.RequestMethod::Put
    Delete => @http.RequestMethod::Delete
    Patch => @http.RequestMethod::Patch
  }
}

///|
pub fn RequestBody::content_type(self : RequestBody) -> String? {
  match self {
    NoBody => None
    JsonBody(_) => Some("application/json")
    TextBody(_) => Some("text/plain")
    BinaryBody(_) => Some("application/octet-stream")
    Ndjson(_) => Some("application/x-ndjson")
  }
}

///|
fn ClientConfig::request_headers(
  self : ClientConfig,
  request : EsRequest,
) -> Map[String, String] {
  let headers = self.default_headers.copy()
  let media_type = self.compatibility.media_type()
  headers["Accept"] = media_type
  match request.body.content_type() {
    Some(content_type) => headers["Content-Type"] = content_type
    None => ()
  }
  match self.auth.authorization_header() {
    Some(value) => headers["Authorization"] = value
    None => ()
  }
  for key, value in request.headers {
    headers[key] = value
  }
  headers
}

///|
async fn write_request_body(client : @http.Client, body : RequestBody) -> Unit {
  match body {
    NoBody => ()
    JsonBody(json) => client.write(json.stringify())
    TextBody(text) => client.write(text)
    BinaryBody(bytes) => client.write(bytes)
    Ndjson(items) => client.write(encode_ndjson(items))
  }
}

///|
fn parse_response_json(data : &@io.Data) -> Json raise EsError {
  let text = data.text() catch { err => raise EsError::Decode(err.to_string()) }
  if text.is_empty() {
    Json::null()
  } else {
    @json.parse(text) catch {
      _ => Json::string(text)
    }
  }
}

///|
pub async fn Client::new(config : ClientConfig) -> Client {
  let inner = @http.Client::new(config.base_url, headers={})
  { config, inner: Some(inner) }
}

///|
pub async fn new(
  base_url : String,
  auth? : Auth = NoAuth,
  compatibility? : ApiCompatibility = Default,
  headers? : Map[String, String] = {},
) -> Client {
  Client::new(ClientConfig::new(base_url, auth~, compatibility~, headers~))
}

///|
pub fn Client::config(self : Client) -> ClientConfig {
  self.config
}

///|
pub fn Client::is_closed(self : Client) -> Bool {
  self.inner is None
}

///|
pub fn Client::close(self : Client) -> Unit {
  match self.inner {
    Some(inner) => {
      inner.close()
      self.inner = None
    }
    None => ()
  }
}

///|
pub async fn Client::perform_json(
  self : Client,
  request : EsRequest,
) -> EsResponse[Json] {
  let inner = match self.inner {
    Some(inner) => inner
    None => raise EsError::ClosedClient
  }
  let target = append_query(request.path, request.query)
  let headers = self.config.request_headers(request)
  inner.request(request.meth.to_http_method(), target, extra_headers=headers)
  write_request_body(inner, request.body)
  let response = inner.end_request()
  let body = parse_response_json(inner.read_all())
  if response.code >= 200 && response.code < 300 {
    { status: response.code, headers: response.headers, body }
  } else {
    raise EsError::Http(status=response.code, reason=response.reason, body~)
  }
}

///|
pub async fn[T : FromJson] Client::perform(
  self : Client,
  request : EsRequest,
) -> EsResponse[T] {
  let response = self.perform_json(request)
  let body : T = @json.from_json(response.body) catch {
    err => raise EsError::Decode(err.to_string())
  }
  { status: response.status, headers: response.headers, body }
}
