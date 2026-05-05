///|
pub(all) enum Auth {
  NoAuth
  ApiKey(String)
  BearerToken(String)
  Basic(String, String)
} derive(Eq, Debug, ToJson)

///|
pub fn Auth::api_key(id~ : String, api_key~ : String) -> Auth {
  let raw = "\{id}:\{api_key}"
  ApiKey(@base64.encode(@utf8.encode(raw)))
}

///|
pub fn Auth::basic(username~ : String, password~ : String) -> Auth {
  Basic(username, password)
}

///|
pub(all) enum ApiCompatibility {
  Default
  CompatibleWith8
} derive(Eq, Debug, ToJson)

///|
pub(all) enum HttpMethod {
  Get
  Head
  Post
  Put
  Delete
  Patch
} derive(Eq, Debug, ToJson)

///|
pub(all) enum RequestBody {
  NoBody
  JsonBody(Json)
  TextBody(String)
  BinaryBody(Bytes)
  Ndjson(Array[Json])
} derive(Eq, Debug, ToJson)

///|
pub(all) struct ClientConfig {
  base_url : String
  auth : Auth
  compatibility : ApiCompatibility
  default_headers : Map[String, String]
} derive(Eq, Debug, ToJson)

///|
pub fn ClientConfig::new(
  base_url : String,
  auth? : Auth = NoAuth,
  compatibility? : ApiCompatibility = Default,
  headers? : Map[String, String] = {},
) -> ClientConfig {
  { base_url, auth, compatibility, default_headers: headers }
}

///|
pub struct Client {
  config : ClientConfig
  mut inner : @http.Client?
}

///|
pub(all) struct EsRequest {
  meth : HttpMethod
  path : String
  query : Array[(String, String)]
  headers : Map[String, String]
  body : RequestBody
} derive(Eq, Debug, ToJson)

///|
pub fn EsRequest::new(
  meth : HttpMethod,
  path : String,
  query? : Array[(String, String)] = [],
  headers? : Map[String, String] = {},
  body? : RequestBody = NoBody,
) -> EsRequest {
  { meth, path, query, headers, body }
}

///|
pub(all) struct EsResponse[T] {
  status : Int
  headers : Map[String, String]
  body : T
} derive(Eq, Debug, ToJson)

///|
pub(all) suberror EsError {
  ClosedClient
  Request(String)
  Decode(String)
  Http(status~ : Int, reason~ : String, body~ : Json)
} derive(Debug, ToJson)

///|
pub(all) struct PathVariant {
  template : String
  required : Array[String]
} derive(Eq, Debug, ToJson)

///|
pub fn PathVariant::new(
  template : String,
  required : Array[String],
) -> PathVariant {
  { template, required }
}
