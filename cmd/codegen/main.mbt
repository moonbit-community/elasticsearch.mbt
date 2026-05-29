///|
enum BodyKind {
  NoBody
  JsonBody(required~ : Bool)
  NdjsonBody(required~ : Bool)
  TextBody(required~ : Bool)
} derive(Debug)

///|
struct PathParam {
  name : String
  field : String
  required : Bool
} derive(Debug)

///|
struct FieldSpec {
  name : String
  field : String
  typ : String
  required : Bool
} derive(Debug)

///|
struct UrlSpec {
  path : String
  required : Array[String]
} derive(Debug)

///|
struct EndpointSpec {
  name : String
  method_name : String
  base_type_name : String
  request_type : String
  query_type : String
  body_type : String?
  response_type : String
  http_method : String
  urls : Array[UrlSpec]
  path_params : Array[PathParam]
  query_fields : Array[FieldSpec]
  body_fields : Array[FieldSpec]
  response_fields : Array[FieldSpec]
  body_kind : BodyKind
} derive(Debug)

///|
let default_input : String = "spec/elasticsearch/v9/schema.json"

///|
let default_root_output : String = "generated_endpoints.mbt"

///|
let default_v9_output : String = "v9/generated.mbt"

///|
fn usage() -> String {
  (
    #|Usage: moon run cmd/codegen --target native -- [--check] [--input FILE] [--root-output FILE] [--v9-output FILE]
    #|
    #|Generate root Client endpoint methods and v9 package wrappers from the vendored Elasticsearch schema.
  )
}

///|
fn parse_args_go(
  args : Array[String],
  check : Bool,
  input : String,
  root_output : String,
  v9_output : String,
) -> (Bool, String, String, String) raise {
  match args {
    ["--check", .. rest] =>
      parse_args_go(rest.to_owned(), true, input, root_output, v9_output)
    ["--input", file, .. rest] =>
      parse_args_go(rest.to_owned(), check, file, root_output, v9_output)
    ["--root-output", file, .. rest] =>
      parse_args_go(rest.to_owned(), check, input, file, v9_output)
    ["--v9-output", file, .. rest] =>
      parse_args_go(rest.to_owned(), check, input, root_output, file)
    ["--output", file, .. rest] =>
      parse_args_go(rest.to_owned(), check, input, root_output, file)
    ["-h" | "--help", ..] => {
      println(usage())
      (check, input, root_output, v9_output)
    }
    [unknown, ..] => fail("unknown codegen option `\{unknown}`")
    [] => (check, input, root_output, v9_output)
  }
}

///|
fn parse_args(args : Array[String]) -> (Bool, String, String, String) raise {
  parse_args_go(
    args, false, default_input, default_root_output, default_v9_output,
  )
}

///|
fn json_field(json : Json, key : String) -> Json? {
  if json is Object(obj) {
    obj.get(key)
  } else {
    None
  }
}

///|
fn json_string_field(json : Json, key : String) -> String? {
  match json_field(json, key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn json_bool_field(json : Json, key : String) -> Bool {
  match json_field(json, key) {
    Some(True) => true
    Some(False) => false
    _ => false
  }
}

///|
fn json_array_field(json : Json, key : String) -> Array[Json] {
  match json_field(json, key) {
    Some(Array(items)) => items
    _ => []
  }
}

///|
fn json_string_array_field(json : Json, key : String) -> Array[String] {
  let out : Array[String] = []
  for item in json_array_field(json, key) {
    if item is String(value) {
      out.push(value)
    }
  }
  out
}

///|
fn mbt_string(value : String) -> String {
  Json::string(value).stringify()
}

///|
fn is_separator(c : Char) -> Bool {
  c == '_' || c == '-' || c == '.'
}

///|
fn to_pascal(name : String) -> String {
  let out = StringBuilder::new(size_hint=name.length())
  let mut next_upper = true
  for c in name {
    if is_separator(c) {
      next_upper = true
    } else if next_upper {
      out.write_char(c.to_ascii_uppercase())
      next_upper = false
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn to_method_name(name : String) -> String {
  let out = StringBuilder::new(size_hint=name.length())
  for c in name {
    if c == '.' || c == '-' {
      out.write_char('_')
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn reserved_word(name : String) -> Bool {
  [
    "as", "async", "alias", "break", "catch", "const", "continue", "else", "enum",
    "defer", "fn", "for", "guard", "if", "impl", "in", "include", "lazy", "let",
    "local", "loop", "match", "method", "mut", "namespace", "raise", "return", "struct",
    "trait", "try", "type", "while",
  ].contains(name)
}

///|
fn field_name(name : String) -> String {
  let out = StringBuilder::new(size_hint=name.length())
  let mut wrote = false
  for c in name {
    if c.is_ascii_alphabetic() || c == '_' {
      out.write_char(c)
      wrote = true
    } else if c.is_ascii_digit() {
      if !wrote {
        out.write_char('_')
      }
      out.write_char(c)
      wrote = true
    } else {
      out.write_char('_')
      wrote = true
    }
  }
  let value = if wrote { out.to_string() } else { "value" }
  if reserved_word(value) {
    value + "_"
  } else {
    value
  }
}

///|
fn unique_field_name(name : String, used : Array[String]) -> String {
  let base = field_name(name)
  let mut candidate = base
  let mut suffix = 2
  while contains_string(used, candidate) {
    candidate = base + "_\{suffix}"
    suffix += 1
  }
  used.push(candidate)
  candidate
}

///|
fn builtin_type_expr(name : String) -> String? {
  match name {
    "string" => Some("String")
    "boolean" => Some("Bool")
    "integer" | "int" | "long" | "short" | "byte" => Some("Int")
    "double" | "float" | "number" => Some("Double")
    _ => None
  }
}

///|
fn instance_type_expr(type_json : Json, string_fallback : Bool) -> String {
  let ref_json = json_field(type_json, "type").unwrap_or(Json::null())
  let name = json_string_field(ref_json, "name").unwrap_or("")
  let ns = json_string_field(ref_json, "namespace").unwrap_or("")
  match builtin_type_expr(name) {
    Some(typ) => typ
    None => if ns == "_builtins" || string_fallback { "String" } else { "Json" }
  }
}

///|
fn spec_type_expr(type_json : Json, string_fallback : Bool) -> String {
  match json_string_field(type_json, "kind").unwrap_or("") {
    "instance_of" => instance_type_expr(type_json, string_fallback)
    "array_of" => {
      let value = json_field(type_json, "value").unwrap_or(Json::null())
      let item_type = spec_type_expr(value, string_fallback)
      if item_type == "Json" {
        "Array[Json]"
      } else {
        "Array[\{item_type}]"
      }
    }
    "dictionary_of" => "Map[String, Json]"
    "user_defined_value" | "union_of" | "literal_value" => "Json"
    _ => if string_fallback { "String" } else { "Json" }
  }
}

///|
fn parse_field_specs(
  fields_json : ArrayView[Json],
  string_fallback : Bool,
) -> Array[FieldSpec] {
  let fields : Array[FieldSpec] = []
  let used : Array[String] = []
  for field_json in fields_json {
    if field_json is Object(_) {
      let name = json_string_field(field_json, "name").unwrap_or("")
      if !name.is_empty() {
        let typ = spec_type_expr(
          json_field(field_json, "type").unwrap_or(Json::null()),
          string_fallback,
        )
        fields.push({
          name,
          field: unique_field_name(name, used),
          typ,
          required: json_bool_field(field_json, "required"),
        })
      }
    }
  }
  fields
}

///|
fn named_type_ref_matches(type_json : Json, ref_json : Json) -> Bool {
  match json_field(type_json, "name") {
    Some(name_json) =>
      json_string_field(name_json, "name") ==
      json_string_field(ref_json, "name") &&
      json_string_field(name_json, "namespace") ==
      json_string_field(ref_json, "namespace")
    None => false
  }
}

///|
fn find_named_type(types : ArrayView[Json], ref_json : Json?) -> Json? {
  match ref_json {
    Some(ref_value) => {
      for type_json in types {
        if named_type_ref_matches(type_json, ref_value) {
          return Some(type_json)
        }
      }
      None
    }
    None => None
  }
}

///|
fn request_path_fields(type_json : Json?) -> Array[FieldSpec] {
  match type_json {
    Some(json) => parse_field_specs(json_array_field(json, "path"), true)
    None => []
  }
}

///|
fn request_query_fields(type_json : Json?) -> Array[FieldSpec] {
  match type_json {
    Some(json) => parse_field_specs(json_array_field(json, "query"), true)
    None => []
  }
}

///|
fn body_property_fields(
  type_json : Json?,
  string_fallback : Bool,
) -> Array[FieldSpec] {
  match type_json {
    Some(json) =>
      match json_field(json, "body") {
        Some(body) =>
          if json_string_field(body, "kind") == Some("properties") {
            parse_field_specs(
              json_array_field(body, "properties"),
              string_fallback,
            )
          } else {
            []
          }
        None => []
      }
    None => []
  }
}

///|
fn request_body_fields(type_json : Json?) -> Array[FieldSpec] {
  body_property_fields(type_json, false)
}

///|
fn response_body_fields(type_json : Json?) -> Array[FieldSpec] {
  body_property_fields(type_json, false)
}

///|
fn merge_path_fields(
  url_params : ArrayView[PathParam],
  spec_params : ArrayView[FieldSpec],
) -> Array[PathParam] {
  if spec_params.length() == 0 {
    url_params.to_owned()
  } else {
    let out : Array[PathParam] = []
    for param in url_params {
      let mut field = param.field
      for spec_param in spec_params {
        if spec_param.name == param.name {
          field = spec_param.field
        }
      }
      out.push({ name: param.name, field, required: param.required })
    }
    out
  }
}

///|
fn contains_string(items : ArrayView[String], needle : String) -> Bool {
  items.any(fn(item) { item == needle })
}

///|
fn push_unique(items : Array[String], value : String) -> Unit {
  if !contains_string(items, value) {
    items.push(value)
  }
}

///|
fn extract_path_params(path : String) -> Array[String] {
  let params : Array[String] = []
  let current = StringBuilder::new()
  let mut in_param = false
  for c in path {
    if c == '{' {
      in_param = true
      current.reset()
    } else if c == '}' {
      if in_param {
        push_unique(params, current.to_string())
      }
      in_param = false
    } else if in_param {
      current.write_char(c)
    }
  }
  params
}

///|
fn sort_urls(urls : Array[UrlSpec]) -> Array[UrlSpec] {
  urls.sort_by(fn(left, right) {
    let l = left.required.length()
    let r = right.required.length()
    if l > r {
      -1
    } else if l < r {
      1
    } else {
      0
    }
  })
  urls
}

///|
fn parse_urls(endpoint_json : Json) -> Array[UrlSpec] {
  let urls : Array[UrlSpec] = []
  for item in json_array_field(endpoint_json, "urls") {
    if item is Object(_) {
      let path = json_string_field(item, "path").unwrap_or("")
      urls.push({ path, required: extract_path_params(path) })
    }
  }
  sort_urls(urls)
}

///|
fn body_kind(endpoint_json : Json) -> BodyKind {
  let media = json_string_array_field(endpoint_json, "requestMediaType")
  let required = json_bool_field(endpoint_json, "requestBodyRequired")
  if contains_string(media, "application/x-ndjson") {
    NdjsonBody(required~)
  } else if contains_string(media, "text/plain") {
    TextBody(required~)
  } else if contains_string(media, "application/json") {
    JsonBody(required~)
  } else {
    NoBody
  }
}

///|
fn body_type_name(base_type_name : String, kind : BodyKind) -> String? {
  match kind {
    NoBody => None
    JsonBody(_) | NdjsonBody(_) | TextBody(_) => Some(base_type_name + "Body")
  }
}

///|
fn body_moon_type(kind : BodyKind) -> String {
  match kind {
    NoBody => "Unit"
    JsonBody(_) => "Json"
    NdjsonBody(_) => "Array[Json]"
    TextBody(_) => "String"
  }
}

///|
fn body_is_required(kind : BodyKind) -> Bool {
  match kind {
    NoBody => false
    JsonBody(required~) | NdjsonBody(required~) | TextBody(required~) =>
      required
  }
}

///|
fn method_variant(meth : String) -> String {
  match meth {
    "GET" => "Get"
    "HEAD" => "Head"
    "POST" => "Post"
    "PUT" => "Put"
    "DELETE" => "Delete"
    _ => "Get"
  }
}

///|
fn choose_method(endpoint_json : Json, kind : BodyKind) -> String {
  let methods : Array[String] = []
  for url in json_array_field(endpoint_json, "urls") {
    for meth in json_string_array_field(url, "methods") {
      push_unique(methods, meth)
    }
  }
  if body_is_required(kind) && contains_string(methods, "POST") {
    "POST"
  } else if !body_is_required(kind) &&
    !kind_is_no_body(kind) &&
    contains_string(methods, "POST") {
    "POST"
  } else {
    methods.get(0).unwrap_or("GET")
  }
}

///|
fn kind_is_no_body(kind : BodyKind) -> Bool {
  kind is NoBody
}

///|
fn build_path_params(urls : ArrayView[UrlSpec]) -> Array[PathParam] {
  let names : Array[String] = []
  for url in urls {
    for param in url.required {
      push_unique(names, param)
    }
  }
  let params : Array[PathParam] = []
  for name in names {
    let mut count = 0
    for url in urls {
      if contains_string(url.required, name) {
        count += 1
      }
    }
    params.push({
      name,
      field: field_name(name),
      required: count == urls.length(),
    })
  }
  params
}

///|
fn parse_endpoint(
  endpoint_json : Json,
  types : ArrayView[Json],
) -> EndpointSpec? {
  if json_bool_field(endpoint_json, "codegenExclude") {
    return None
  }
  let name = json_string_field(endpoint_json, "name").unwrap_or("")
  if name.is_empty() {
    return None
  }
  let base_type_name = to_pascal(name)
  let kind = body_kind(endpoint_json)
  let urls = parse_urls(endpoint_json)
  let request_type_json = find_named_type(
    types,
    json_field(endpoint_json, "request"),
  )
  let response_type_json = find_named_type(
    types,
    json_field(endpoint_json, "response"),
  )
  let spec_path_params = request_path_fields(request_type_json)
  Some({
    name,
    method_name: to_method_name(name),
    base_type_name,
    request_type: base_type_name + "Request",
    query_type: base_type_name + "Query",
    body_type: body_type_name(base_type_name, kind),
    response_type: base_type_name + "Response",
    http_method: method_variant(choose_method(endpoint_json, kind)),
    urls,
    path_params: merge_path_fields(build_path_params(urls), spec_path_params),
    query_fields: request_query_fields(request_type_json),
    body_fields: request_body_fields(request_type_json),
    response_fields: response_body_fields(response_type_json),
    body_kind: kind,
  })
}

///|
fn parse_schema(json : Json) -> Array[EndpointSpec] {
  let types = json_array_field(json, "types")
  let endpoints : Array[EndpointSpec] = []
  for endpoint_json in json_array_field(json, "endpoints") {
    match parse_endpoint(endpoint_json, types) {
      Some(endpoint) => endpoints.push(endpoint)
      None => ()
    }
  }
  endpoints
}

///|
fn render_string_array(items : ArrayView[String]) -> String {
  let out = StringBuilder::new()
  out.write_char('[')
  let mut first = true
  for item in items {
    if first {
      first = false
    } else {
      out.write_string(", ")
    }
    out.write_string(mbt_string(item))
  }
  out.write_char(']')
  out.to_string()
}

///|
fn render_url_variants(urls : ArrayView[UrlSpec]) -> String {
  let out = StringBuilder::new()
  if urls.length() == 1 {
    out.write_char('[')
    for url in urls {
      out.write_string("PathVariant::new(")
      out.write_string(mbt_string(url.path))
      out.write_string(", ")
      out.write_string(render_string_array(url.required))
      out.write_char(')')
    }
    out.write_char(']')
  } else {
    out.write_string("[\n")
    for url in urls {
      out.write_string("      PathVariant::new(")
      out.write_string(mbt_string(url.path))
      out.write_string(", ")
      out.write_string(render_string_array(url.required))
      out.write_string("),\n")
    }
    out.write_string("    ]")
  }
  out.to_string()
}

///|
fn write_field_lines(
  out : StringBuilder,
  fields : ArrayView[FieldSpec],
) -> Unit {
  for field in fields {
    let typ = if field.required { field.typ } else { field.typ + "?" }
    out.write_string("  \{field.field} : \{typ}\n")
  }
}

///|
fn write_json_to_json_impl(
  out : StringBuilder,
  type_name : String,
  fields : ArrayView[FieldSpec],
) -> Unit {
  let receiver = if fields.length() == 0 { "_self" } else { "self" }
  out.write_string("///|\n")
  out.write_string(
    "pub impl ToJson for \{type_name} with fn to_json(\{receiver} : \{type_name}) -> Json {\n",
  )
  out.write_string("  let obj : Map[String, Json] = {}\n")
  for field in fields {
    if field.required {
      out.write_string(
        "  obj[\{mbt_string(field.name)}] = \{receiver}.\{field.field}.to_json()\n",
      )
    } else {
      out.write_string(
        "  match \{receiver}.\{field.field} {\n    Some(value) => obj[\{mbt_string(field.name)}] = value.to_json()\n    None => ()\n  }\n",
      )
    }
  }
  out.write_string("  Json::object(obj)\n")
  out.write_string("}\n\n")
}

///|
fn write_json_from_json_impl(
  out : StringBuilder,
  type_name : String,
  fields : ArrayView[FieldSpec],
) -> Unit {
  let error_message = mbt_string(type_name + ": expected object")
  out.write_string("///|\n")
  out.write_string(
    "pub impl FromJson for \{type_name} with fn from_json(json, path) {\n",
  )
  if fields.length() == 0 {
    out.write_string(
      "  guard json is Object(_) || json is Null else {\n    raise @json.JsonDecodeError((path, \{error_message}))\n  }\n",
    )
    out.write_string("  \{type_name}::{}\n")
  } else {
    out.write_string(
      "  guard json is Object(obj) else {\n    raise @json.JsonDecodeError((path, \{error_message}))\n  }\n",
    )
    out.write_string("  {\n")
    for field in fields {
      let field_key = mbt_string(field.name)
      if field.required {
        out.write_string(
          "    \{field.field}: @json.from_json(obj.get(\{field_key}).unwrap_or(Json::null()), path=path.add_key(\{field_key})),\n",
        )
      } else {
        out.write_string(
          "    \{field.field}: match obj.get(\{field_key}) {\n      Some(Null) => None\n      None => None\n      Some(value) => Some(@json.from_json(value, path=path.add_key(\{field_key})))\n    },\n",
        )
      }
    }
    out.write_string("  }\n")
  }
  out.write_string("}\n\n")
}

///|
fn write_value_constructor(
  out : StringBuilder,
  type_name : String,
  fields : ArrayView[FieldSpec],
) -> Unit {
  out.write_string("///|\n")
  out.write_string("pub fn \{type_name}::new(\n")
  for field in fields {
    if field.required {
      out.write_string("  \{field.field} : \{field.typ},\n")
    }
  }
  for field in fields {
    if !field.required {
      out.write_string("  \{field.field}? : \{field.typ},\n")
    }
  }
  out.write_string(") -> \{type_name} {\n")
  if fields.length() == 0 {
    out.write_string("  \{type_name}::{}\n")
  } else {
    out.write_string("  { ")
    let mut first = true
    for field in fields {
      if first {
        first = false
      } else {
        out.write_string(", ")
      }
      out.write_string(field.field)
    }
    if fields.length() == 1 {
      out.write_char(',')
    }
    out.write_string(" }\n")
  }
  out.write_string("}\n\n")
}

///|
fn query_is_required(endpoint : EndpointSpec) -> Bool {
  endpoint.query_fields.any(fn(field) { field.required })
}

///|
fn body_uses_json_struct(endpoint : EndpointSpec) -> Bool {
  endpoint.body_fields.length() > 0 && endpoint.body_kind is JsonBody(_)
}

///|
fn write_json_struct(
  out : StringBuilder,
  type_name : String,
  fields : ArrayView[FieldSpec],
  add_constructor : Bool,
) -> Unit {
  out.write_string("///|\n")
  out.write_string("pub(all) struct \{type_name} {\n")
  write_field_lines(out, fields)
  out.write_string("} derive(Eq, Debug)\n\n")
  write_json_to_json_impl(out, type_name, fields)
  write_json_from_json_impl(out, type_name, fields)
  if add_constructor {
    write_value_constructor(out, type_name, fields)
  }
}

///|
fn write_query_to_pairs(out : StringBuilder, endpoint : EndpointSpec) -> Unit {
  let receiver = if endpoint.query_fields.length() == 0 {
    "_self"
  } else {
    "self"
  }
  out.write_string("///|\n")
  out.write_string(
    "pub fn \{endpoint.query_type}::to_pairs(\{receiver} : \{endpoint.query_type}) -> Array[(String, String)] {\n",
  )
  out.write_string("  let pairs : Array[(String, String)] = []\n")
  for field in endpoint.query_fields {
    if field.required {
      out.write_string(
        "  push_query_json(pairs, \{mbt_string(field.name)}, \{receiver}.\{field.field}.to_json())\n",
      )
    } else {
      out.write_string(
        "  match \{receiver}.\{field.field} {\n    Some(value) => push_query_json(pairs, \{mbt_string(field.name)}, value.to_json())\n    None => ()\n  }\n",
      )
    }
  }
  out.write_string("  pairs\n")
  out.write_string("}\n\n")
}

///|
fn write_query_type(out : StringBuilder, endpoint : EndpointSpec) -> Unit {
  write_json_struct(out, endpoint.query_type, endpoint.query_fields, true)
  write_query_to_pairs(out, endpoint)
}

///|
fn write_body_type(out : StringBuilder, endpoint : EndpointSpec) -> Unit {
  match endpoint.body_type {
    Some(body_type) =>
      if body_uses_json_struct(endpoint) {
        write_json_struct(out, body_type, endpoint.body_fields, true)
      } else {
        out.write_string("///|\n")
        out.write_string(
          "pub type \{body_type} = \{body_moon_type(endpoint.body_kind)}\n\n",
        )
      }
    None => ()
  }
}

///|
fn write_response_type(out : StringBuilder, endpoint : EndpointSpec) -> Unit {
  if endpoint.response_fields.length() > 0 {
    write_json_struct(
      out,
      endpoint.response_type,
      endpoint.response_fields,
      false,
    )
  } else {
    out.write_string("///|\n")
    out.write_string("pub type \{endpoint.response_type} = Json\n\n")
  }
}

///|
fn write_request_struct(out : StringBuilder, endpoint : EndpointSpec) -> Unit {
  out.write_string("///|\n")
  out.write_string("pub(all) struct \{endpoint.request_type} {\n")
  for param in endpoint.path_params {
    let typ = if param.required { "String" } else { "String?" }
    out.write_string("  \{param.field} : \{typ}\n")
  }
  out.write_string("  query : \{endpoint.query_type}\n")
  match endpoint.body_type {
    Some(body_type) => {
      let typ = if body_is_required(endpoint.body_kind) {
        body_type
      } else {
        body_type + "?"
      }
      out.write_string("  body : \{typ}\n")
    }
    None => ()
  }
  out.write_string("} derive(Eq, Debug, ToJson, FromJson)\n\n")
}

///|
fn write_constructor_params(
  out : StringBuilder,
  endpoint : EndpointSpec,
) -> Unit {
  for param in endpoint.path_params {
    if param.required {
      out.write_string("  \{param.field} : String,\n")
    }
  }
  match endpoint.body_type {
    Some(body_type) =>
      if body_is_required(endpoint.body_kind) {
        out.write_string("  body : \{body_type},\n")
      }
    None => ()
  }
  for param in endpoint.path_params {
    if !param.required {
      out.write_string("  \{param.field}? : String,\n")
    }
  }
  if query_is_required(endpoint) {
    out.write_string("  query : \{endpoint.query_type},\n")
  } else {
    out.write_string(
      "  query? : \{endpoint.query_type} = \{endpoint.query_type}::new(),\n",
    )
  }
  match endpoint.body_type {
    Some(body_type) =>
      if !body_is_required(endpoint.body_kind) {
        out.write_string("  body? : \{body_type},\n")
      }
    None => ()
  }
}

///|
fn write_constructor(out : StringBuilder, endpoint : EndpointSpec) -> Unit {
  out.write_string("///|\n")
  out.write_string("pub fn \{endpoint.request_type}::new(\n")
  write_constructor_params(out, endpoint)
  out.write_string(") -> \{endpoint.request_type} {\n")
  let fields : Array[String] = []
  for param in endpoint.path_params {
    fields.push(param.field)
  }
  fields.push("query")
  match endpoint.body_type {
    Some(_) => fields.push("body")
    None => ()
  }
  out.write_string("  { ")
  let mut first = true
  for field in fields {
    if first {
      first = false
    } else {
      out.write_string(", ")
    }
    out.write_string(field)
  }
  if fields.length() == 1 {
    out.write_char(',')
  }
  out.write_string(" }\n")
  out.write_string("}\n\n")
}

///|
fn write_params_map(out : StringBuilder, endpoint : EndpointSpec) -> Unit {
  out.write_string("  let params : Map[String, String] = {}\n")
  for param in endpoint.path_params {
    if param.required {
      out.write_string(
        "  params[\{mbt_string(param.name)}] = request.\{param.field}\n",
      )
    } else {
      out.write_string(
        "  match request.\{param.field} {\n    Some(value) => params[\{mbt_string(param.name)}] = value\n    None => ()\n  }\n",
      )
    }
  }
}

///|
fn write_client_method(out : StringBuilder, endpoint : EndpointSpec) -> Unit {
  out.write_string("///|\n")
  out.write_string("pub async fn Client::\{endpoint.method_name}(\n")
  out.write_string("  self : Client,\n")
  out.write_string("  request : \{endpoint.request_type},\n")
  out.write_string(") -> EsResponse[\{endpoint.response_type}] {\n")
  write_params_map(out, endpoint)
  out.write_string("  let query = request.query.to_pairs()\n")
  out.write_string("  let path = select_path(\n    ")
  out.write_string(render_url_variants(endpoint.urls))
  out.write_string(",\n    params\n  )\n")
  if kind_is_no_body(endpoint.body_kind) {
    if endpoint.response_fields.length() > 0 {
      out.write_string(
        "  self.perform(EsRequest::new(\{endpoint.http_method}, path, query~))\n",
      )
    } else {
      out.write_string(
        "  self.perform_json(EsRequest::new(\{endpoint.http_method}, path, query~))\n",
      )
    }
  } else {
    let body_to_json = body_uses_json_struct(endpoint)
    match endpoint.body_kind {
      JsonBody(required~) =>
        if required {
          if body_to_json {
            out.write_string("  let body = JsonBody(request.body.to_json())\n")
          } else {
            out.write_string("  let body = JsonBody(request.body)\n")
          }
        } else if body_to_json {
          out.write_string(
            "  let body = match request.body {\n    Some(value) => JsonBody(value.to_json())\n    None => NoBody\n  }\n",
          )
        } else {
          out.write_string(
            "  let body = match request.body {\n    Some(value) => JsonBody(value)\n    None => NoBody\n  }\n",
          )
        }
      NdjsonBody(required~) =>
        if required {
          out.write_string("  let body = Ndjson(request.body)\n")
        } else {
          out.write_string(
            "  let body = match request.body {\n    Some(value) => Ndjson(value)\n    None => NoBody\n  }\n",
          )
        }
      TextBody(required~) =>
        if required {
          out.write_string("  let body = TextBody(request.body)\n")
        } else {
          out.write_string(
            "  let body = match request.body {\n    Some(value) => TextBody(value)\n    None => NoBody\n  }\n",
          )
        }
      NoBody => out.write_string("  let body = NoBody\n")
    }
    if endpoint.response_fields.length() > 0 {
      out.write_string(
        "  self.perform(EsRequest::new(\{endpoint.http_method}, path, query~, body~))\n",
      )
    } else {
      out.write_string(
        "  self.perform_json(EsRequest::new(\{endpoint.http_method}, path, query~, body~))\n",
      )
    }
  }
  out.write_string("}\n")
}

///|
fn write_root_endpoint(out : StringBuilder, endpoint : EndpointSpec) -> Unit {
  write_query_type(out, endpoint)
  write_body_type(out, endpoint)
  write_response_type(out, endpoint)
  write_request_struct(out, endpoint)
  write_constructor(out, endpoint)
  write_client_method(out, endpoint)
}

///|
fn generate_root(endpoints : ArrayView[EndpointSpec]) -> String {
  let out = StringBuilder::new()
  out.write_string("// Generated by `moon run cmd/codegen`; DO NOT EDIT.\n\n")
  let mut first = true
  for endpoint in endpoints {
    if first {
      first = false
    } else {
      out.write_string("\n")
    }
    write_root_endpoint(out, endpoint)
  }
  out.to_string()
}

///|
fn write_v9_endpoint(out : StringBuilder, endpoint : EndpointSpec) -> Unit {
  out.write_string("///|\n")
  out.write_string(
    "pub type \{endpoint.query_type} = @es.\{endpoint.query_type}\n\n",
  )
  match endpoint.body_type {
    Some(body_type) => {
      out.write_string("///|\n")
      out.write_string("pub type \{body_type} = @es.\{body_type}\n\n")
    }
    None => ()
  }
  out.write_string("///|\n")
  out.write_string(
    "pub type \{endpoint.request_type} = @es.\{endpoint.request_type}\n\n",
  )
  out.write_string("///|\n")
  out.write_string(
    "pub type \{endpoint.response_type} = @es.\{endpoint.response_type}\n\n",
  )
  out.write_string("///|\n")
  out.write_string("pub async fn \{endpoint.method_name}(\n")
  out.write_string("  client : @es.Client,\n")
  out.write_string("  request : \{endpoint.request_type},\n")
  out.write_string(") -> @es.EsResponse[\{endpoint.response_type}] {\n")
  out.write_string("  client.\{endpoint.method_name}(request)\n")
  out.write_string("}\n")
}

///|
fn generate_v9(endpoints : ArrayView[EndpointSpec]) -> String {
  let out = StringBuilder::new()
  out.write_string("// Generated by `moon run cmd/codegen`; DO NOT EDIT.\n\n")
  let mut first = true
  for endpoint in endpoints {
    if first {
      first = false
    } else {
      out.write_string("\n")
    }
    write_v9_endpoint(out, endpoint)
  }
  out.to_string()
}

///|
async fn read_schema(path : String) -> Array[EndpointSpec] {
  let json = @json.parse(@fs.read_file(path).text())
  parse_schema(json)
}

///|
fn is_source_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == ','
}

///|
fn compact_source(source : String) -> String {
  let out = StringBuilder::new(size_hint=source.length())
  for c in source {
    if !is_source_whitespace(c) {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
async fn check_file(path : String, expected : String) -> Unit {
  let current = @fs.read_file(path).text()
  if compact_source(current) != compact_source(expected) {
    fail("generated file is stale: run `moon run cmd/codegen --target native`")
  }
}

///|
async fn main {
  let (check, input, root_output, v9_output) = parse_args(
    @env.args()[1:].to_owned(),
  )
  let endpoints = read_schema(input)
  let root_generated = generate_root(endpoints)
  let v9_generated = generate_v9(endpoints)
  if check {
    check_file(root_output, root_generated)
    check_file(v9_output, v9_generated)
  } else {
    @fs.write_file(root_output, root_generated, create=0o644, truncate=true)
    @fs.write_file(v9_output, v9_generated, create=0o644, truncate=true)
  }
}
