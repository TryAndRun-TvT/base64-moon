///|
test "encode_standard_padding_forms" {
  // RFC 4648 §10：三种余数的标准测试向量
  assert_eq(@lib.encode(b"f"), "Zg==")
  assert_eq(@lib.encode(b"fo"), "Zm8=")
  assert_eq(@lib.encode(b"foo"), "Zm9v")
  assert_eq(@lib.encode(b"foob"), "Zm9vYg==")
  assert_eq(@lib.encode(b"fooba"), "Zm9vYmE=")
  assert_eq(@lib.encode(b"foobar"), "Zm9vYmFy")
}

///|
test "encode_urlsafe_uses_alt_chars" {
  // URL-safe 字母表把 `+` / `/` 换成 `-` / `_`（RFC 4648 §5 向量）
  assert_eq(
    @lib.encode(b"\xfb\xff", alphabet=@lib.Alphabet::url_safe()),
    "-_8=",
  )
  assert_eq(@lib.encode(b"\xfb\xff"), "+/8=")
}

///|
test "decode_round_trips_and_rejects_invalid" {
  assert_eq(@lib.decode("Zm9vYmFy").unwrap(), b"foobar")
  assert_eq(@lib.decode("Zm9vYmFy=").unwrap(), b"foobar")
  assert_eq(
    @lib.decode("-_8=", alphabet=@lib.Alphabet::url_safe()).unwrap(),
    b"\xfb\xff",
  )
  assert_eq(@lib.decode("Zm9v!"), Err("invalid base64 character: !"))
}
