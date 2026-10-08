///|
/// **MoonBit 官方 core** 的同口径出口 —— 同平台对照（都在 wasm-gc 上）。
///
/// 【为什么这个对照最干净】本库与 core 是**同一门语言、同一个运行时、同一个后端**；
/// 差别只有实现本身。故这一格是「本库 vs core 到底谁快」的**唯一**有效证据，
/// 也对应 [S9 §3.2] 登记的「3.3–4.6×」那条结论——它值得有个可复跑的出口。
///
/// 【为什么 core 侧没有「内核段」】core 只导出 `encode` / `decode`
/// （返回 `String` / `Bytes`，天生含物化），**没有** `encode_slice` 这一类零分配入口。
/// 故与 core 的对照只能在**端到端**层做——这正是 [S7 §2.1] 要素 ①
/// 「分子分母同层」的适用：跨实现比较时，选择**双方都有**的那一层。
///
/// 注意 core 的 `decode` 收 `StringView`（是 UTF-16 视图），故输入要从
/// base64 串再走一遍 `String`——这层转换**两侧都会有**（本库 `decode` 收 `BytesView`，
/// 也要从串转字节），故仍在同层。

///|
/// 与 core 的**端到端**往返对照：`reps` 次 encode → decode。
#export_name("bench_core_roundtrip")
pub fn bench_core_roundtrip(n : Int, seed : Int, reps : Int) -> Int {
  let src = Bytes::from_array(det_bytes(n, seed))
  let mut acc = 0
  let mut r = 0
  while r < reps {
    let encoded = @base64.encode(src)
    let decoded = try @base64.decode(encoded) catch {
      _ => return -1
    }
    acc = acc + checksum(decoded)
    r = r + 1
  }
  acc
}

///|
/// core 侧的编码输出校验和（供跨实现一致性校验把 core 也纳入）。
#export_name("verify_core_encode")
pub fn verify_core_encode(n : Int, seed : Int) -> Int {
  checksum(@utf8.encode(@base64.encode(Bytes::from_array(det_bytes(n, seed))))[:])
}

///|
/// core 侧的往返校验和（同上）。
#export_name("verify_core_roundtrip")
pub fn verify_core_roundtrip(n : Int, seed : Int) -> Int {
  let src = Bytes::from_array(det_bytes(n, seed))
  let decoded = try @base64.decode(@base64.encode(src)) catch { _ => return -1 }
  if checksum(decoded) != checksum(src[:]) {
    return -1
  }
  checksum(decoded)
}

// ── core 侧分向基准（与 §3 端到端同层，只是拆开 encode / decode）───────────────

///|
/// core 侧**只编码**：`reps` 次 `@base64.encode`，回传编码串校验和。
#export_name("bench_core_encode_only")
pub fn bench_core_encode_only(n : Int, seed : Int, reps : Int) -> Int {
  let src = Bytes::from_array(det_bytes(n, seed))
  let mut acc = 0
  let mut r = 0
  while r < reps {
    acc = acc + checksum(@utf8.encode(@base64.encode(src))[:])
    r = r + 1
  }
  acc
}

///|
/// core 侧**只解码**：`reps` 次 `@base64.decode`，回传解码结果校验和。
#export_name("bench_core_decode_only")
pub fn bench_core_decode_only(n : Int, seed : Int, reps : Int) -> Int {
  let encoded = @base64.encode(Bytes::from_array(det_bytes(n, seed)))
  let mut acc = 0
  let mut r = 0
  while r < reps {
    let decoded = try @base64.decode(encoded) catch { _ => return -1 }
    acc = acc + checksum(decoded)
    r = r + 1
  }
  acc
}
