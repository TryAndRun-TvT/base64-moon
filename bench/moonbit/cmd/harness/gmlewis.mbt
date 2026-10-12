///|
/// **第三方 MoonBit 实现** gmlewis/base64 的同口径出口（同语言、同运行时、同后端）。
///
/// 【为什么要这一家】`moonbit-core` 是官方 core（同平台但不同定位），
/// 而 `gmlewis/base64` 是 mooncakes 上**另一个独立发布的 base64 实现**——
/// 它才是「同一个 wasm-gc 平台上，别人写的 base64 有多快」的直接对照。
/// 与 core 同属「同一门语言 / 同一运行时 / 同一后端」，故是可比的一格。
///
/// 【API 形态】gmlewis 只导出端到端入口（`std_encode2str` / `std_encode2bytes` /
/// `std_decode2bytes`），**没有**零分配内核段——与 core 同款，故对照只在端到端层做
/// （跨实现比较选**双方都有**的那层，bench/README.md 口径要素 ①）。
///
/// 【语义前提】`std_encode2str` 默认带 `=` 填充，与 STANDARD 一致；
/// `std_decode2bytes` 收 `String`（UTF-16），与 core 侧同款——本库 `decode` 收
/// `BytesView` 同样要从串转字节，故这层转换**两侧都有**，仍在同层。

///|
/// 与 gmlewis 的**端到端**往返对照：`reps` 次 encode → decode。
#export_name("bench_gmlewis_roundtrip")
pub fn bench_gmlewis_roundtrip(n : Int32, seed : Int32, reps : Int32) -> Int32 {
  let src = det_bytes(n, seed)
  let mut acc = 0
  let mut r = 0
  while r < reps {
    let encoded = @gmlewis.std_encode2str(src)
    let decoded = @gmlewis.std_decode2bytes(encoded) catch { _ => return -1 }
    acc = acc + checksum(decoded)
    r = r + 1
  }
  acc
}

///|
/// gmlewis 侧**只编码**：`reps` 次 `std_encode2str`，回传编码串校验和。
#export_name("bench_gmlewis_encode_only")
pub fn bench_gmlewis_encode_only(
  n : Int32,
  seed : Int32,
  reps : Int32,
) -> Int32 {
  let src = det_bytes(n, seed)
  let mut acc = 0
  let mut r = 0
  while r < reps {
    acc = acc + checksum(@utf8.encode(@gmlewis.std_encode2str(src))[:])
    r = r + 1
  }
  acc
}

///|
/// gmlewis 侧**只解码**：`reps` 次 `std_decode2bytes`，回传解码结果校验和。
///
/// 输入是**被测侧自己编出来的**合法 base64，与往返里 decode 用同一份输入。
#export_name("bench_gmlewis_decode_only")
pub fn bench_gmlewis_decode_only(
  n : Int32,
  seed : Int32,
  reps : Int32,
) -> Int32 {
  let encoded = @gmlewis.std_encode2str(det_bytes(n, seed))
  let mut acc = 0
  let mut r = 0
  while r < reps {
    let decoded = @gmlewis.std_decode2bytes(encoded) catch { _ => return -1 }
    acc = acc + checksum(decoded)
    r = r + 1
  }
  acc
}

///|
/// gmlewis 侧的编码输出校验和（供跨实现一致性校验把它也纳入）。
#export_name("verify_gmlewis_encode")
pub fn verify_gmlewis_encode(n : Int32, seed : Int32) -> Int32 {
  checksum(@utf8.encode(@gmlewis.std_encode2str(det_bytes(n, seed)))[:])
}

///|
/// gmlewis 侧的往返校验和（同上）。
#export_name("verify_gmlewis_roundtrip")
pub fn verify_gmlewis_roundtrip(n : Int32, seed : Int32) -> Int32 {
  let src = det_bytes(n, seed)
  let encoded = @gmlewis.std_encode2str(src)
  let decoded = @gmlewis.std_decode2bytes(encoded) catch { _ => return -1 }
  if checksum(decoded) != checksum(Bytes::from_array(src)[:]) {
    return -1
  }
  checksum(decoded)
}
