///|
fn is_unreserved_byte(byte : Byte) -> Bool {
  let n = byte.to_int()
  (n >= 0x41 && n <= 0x5A) ||
  (n >= 0x61 && n <= 0x7A) ||
  (n >= 0x30 && n <= 0x39) ||
  n == 0x2D ||
  n == 0x2E ||
  n == 0x5F ||
  n == 0x7E
}

///|
pub fn percent_encode(value : String) -> String {
  let out = StringBuilder::new(size_hint=value.length())
  for byte in @utf8.encode(value) {
    if is_unreserved_byte(byte) {
      out.write_char(byte.to_char())
    } else {
      out.write_char('%')
      out.write_string(byte.to_hex().to_upper())
    }
  }
  out.to_string()
}

///|
pub fn encode_query(query : ArrayView[(String, String)]) -> String {
  let out = StringBuilder::new()
  let mut first = true
  for pair in query {
    let (key, value) = pair
    if first {
      first = false
    } else {
      out.write_char('&')
    }
    out.write_string(percent_encode(key))
    out.write_char('=')
    out.write_string(percent_encode(value))
  }
  out.to_string()
}

///|
pub fn append_query(
  path : String,
  query : ArrayView[(String, String)],
) -> String {
  if query.length() == 0 {
    path
  } else {
    path + "?" + encode_query(query)
  }
}

///|
pub fn encode_ndjson(items : ArrayView[Json]) -> String {
  let out = StringBuilder::new()
  for item in items {
    out.write_string(item.stringify())
    out.write_char('\n')
  }
  out.to_string()
}

///|
fn query_json_value_to_string(value : Json) -> String {
  match value {
    String(text) => text
    True => "true"
    False => "false"
    Array(items) => {
      let out = StringBuilder::new()
      let mut first = true
      for item in items {
        if first {
          first = false
        } else {
          out.write_char(',')
        }
        out.write_string(query_json_value_to_string(item))
      }
      out.to_string()
    }
    Null => ""
    _ => value.stringify()
  }
}

///|
fn push_query_json(
  pairs : Array[(String, String)],
  name : String,
  value : Json,
) -> Unit {
  if value is Null {
    return
  }
  pairs.push((name, query_json_value_to_string(value)))
}

///|
fn has_required_params(
  required : ArrayView[String],
  params : Map[String, String],
) -> Bool {
  required.all(fn(key) { params.get(key) is Some(_) })
}

///|
pub fn render_path_template(
  template : String,
  params : Map[String, String],
) -> String raise EsError {
  let mut rendered = template
  for key, value in params {
    rendered = rendered.replace_all(old="{\{key}}", new=percent_encode(value))
  }
  if rendered.contains("{") || rendered.contains("}") {
    raise EsError::Request("unbound path parameter in `\{template}`")
  }
  rendered
}

///|
pub fn select_path(
  variants : ArrayView[PathVariant],
  params : Map[String, String],
) -> String raise EsError {
  let mut selected : PathVariant? = None
  for variant in variants {
    if selected is None && has_required_params(variant.required, params) {
      selected = Some(variant)
    }
  }
  match selected {
    Some(variant) => render_path_template(variant.template, params)
    None => raise EsError::Request("no matching path variant")
  }
}
