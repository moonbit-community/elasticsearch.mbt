///|
test "v9 aliases root generated request types" {
  let request = SearchRequest::new(
    index="logs",
    body=SearchBody::new(query=Json::object({})),
  )
  assert_true(request.index == Some("logs"))
}
