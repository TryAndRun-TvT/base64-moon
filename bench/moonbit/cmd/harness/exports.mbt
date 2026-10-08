///|
/// 基准 harness 的**跨界出口**（`#export_name` ⇒ wasm 导出）。
///
/// 【契约】所有出口的签名只含 `Int`，返回 `Int`（理由见 `moon.pkg`：GC 对象取不出）。
///
/// 【为什么把循环**放在被测侧**】宿主侧循环 = 每次跨界都要跨一次 JS↔wasm 边界，
/// 且 Node 的计时粒度套在单次调用上，量到的是边界开销而非算法。
/// 故约定：**调用方给 `reps`，被测侧自己循环 `reps` 次并回传累加值**。
/// 这同时把「计时器唯一」（README 口径 ②）落成结构约束：被测侧**不计时**。
///
/// 【内核段用 `*_slice` 而非 `encode`/`decode`】`encode` 每次调用都建引擎 + 物化
/// `String`，端到端才该用它。内核段要对齐的是「同层对照」这一条口径
/// （[S7 §2.1] 要素 ①）：`encode_slice` / `decode_slice` 是**零分配内核**的公共入口，
/// 与 Rust 侧的 `encode_slice` / `decode_slice` 一一对应。

///|
/// 编码**内核**基准：`reps` 次 `encode_slice`（**不含** `Engine::new`，不物化 String）。
///
/// 返回写入字节数的累加和——防 DCE（README 口径 ④）。
#export_name("bench_encode_slice")
pub fn bench_encode_slice(n : Int, seed : Int, reps : Int) -> Int {
  let src = Bytes::from_array(det_bytes(n, seed))
  let out = FixedArray::make((n + 2) / 3 * 4, b'\x00')
  let mut acc = 0
  let mut r = 0
  while r < reps {
    match @lib.encode_slice(src[:], out) {
      Ok(len) => acc = acc + len
      Err(_) => acc = acc - 1
    }
    r = r + 1
  }
  acc
}

///|
/// 解码**内核**基准：`reps` 次 `decode_slice`（**不含** `Engine::new`，不物化 Bytes）。
#export_name("bench_decode_slice")
pub fn bench_decode_slice(n : Int, seed : Int, reps : Int) -> Int {
  let encoded = @utf8.encode(@lib.encode(Bytes::from_array(det_bytes(n, seed))))
  let out = FixedArray::make(decoded_upper_bound(encoded.length()), b'\x00')
  let mut acc = 0
  let mut r = 0
  while r < reps {
    match @lib.decode_slice(encoded, out) {
      Ok(len) => acc = acc + len
      Err(_) => acc = acc - 1
    }
    r = r + 1
  }
  acc
}

///|
/// 解码输出长度的**上界**（`(len / 4 + (len % 4 > 0)) * 3`）。
///
/// 这里**按 RFC 定义重算一遍**、不去 import 内核的 `decoded_len_estimate`：
/// 那是 internal 包，harness 不得 import（可见性规则）。重算的代价是
/// 「算式可能与本库不符」——故它由 `verify_roundtrip` 的真实往返兜住：
/// 算式错了，解码要么报错要么校验和不符，bench.sh 直接红。
fn decoded_upper_bound(len : Int) -> Int {
  let rem = len % 4
  (len / 4 + (if rem > 0 { 1 } else { 0 })) * 3
}

///|
/// **往返**基准：`reps` 次 encode → decode，回传解码结果的校验和。
///
/// 「往返」= 一次 encode + 一次 decode，是各侧**唯一**的统一被测量
/// （Rust / JS 侧同样只导出往返），故跨实现对比只在这个口径上做。
#export_name("bench_roundtrip")
pub fn bench_roundtrip(n : Int, seed : Int, reps : Int) -> Int {
  let src = det_bytes(n, seed)
  let mut acc = 0
  let mut r = 0
  while r < reps {
    let encoded = @lib.encode(Bytes::from_array(src))
    let decoded = @lib.decode(@utf8.encode(encoded)[:]).unwrap()
    acc = acc + checksum(decoded)
    r = r + 1
  }
  acc
}

///|
/// 往返**校验**（单次，不计时）：回传解码结果校验和，供跨实现逐位对账。
///
/// 与 `bench_roundtrip(n, seed, 1)` 的区别：本函数**不参与计时**，
/// 是「先证明各家在算同一件事」的那一步。判等失败时 bench.sh 直接红。
#export_name("verify_roundtrip")
pub fn verify_roundtrip(n : Int, seed : Int) -> Int {
  let src = Bytes::from_array(det_bytes(n, seed))
  let encoded = @lib.encode(src)
  let decoded = @lib.decode(@utf8.encode(encoded)[:]).unwrap()
  // 同时校验「解出来 == 原数据」：否则校验和相等也可能是一起错。
  if checksum(decoded) != checksum(src[:]) {
    return -1
  }
  checksum(decoded)
}

///|
/// 编码输出校验和（单次）：供跨实现比对**编码串**是否逐字节相同。
#export_name("verify_encode")
pub fn verify_encode(n : Int, seed : Int) -> Int {
  checksum(@utf8.encode(@lib.encode(Bytes::from_array(det_bytes(n, seed))))[:])
}

// ── 分向（encode-only / decode-only）基准 ─────────────────────────────────────
//
// 【为什么往返之外还要分向】往返 = 编码 + 解码，把两条腿的差异**合成一个数**。
// 外部对照（E1 §3.3）已显示本库「解码是弱腿」——但如果只报往返，
// 这条结论就无法从表里直接读出，只能靠内核段的间接证据推断。
// 分向表让「编码多快 / 解码多快」各自成为可引用的一行。
//
// 【与内核段的区别】这里是**端到端**分向（含引擎构造与物化），不是 `*_slice`。
// 理由：内核段 JS 侧没有对应层，无法横向比；分向表要的是「6 家都能算」的那一层。
// 内核段仍只在 MoonBit vs Rust 之间比（E1 §3.3）。

///|
/// **只编码**基准：`reps` 次 `@lib.encode`，回传编码串校验和。
///
/// 与 `bench_roundtrip` 的区别：**不含 decode**。两者相减即为解码段耗时
/// （同一物化口径下），故分向表与往返表**互相校验**。
#export_name("bench_encode_only")
pub fn bench_encode_only(n : Int, seed : Int, reps : Int) -> Int {
  let src = det_bytes(n, seed)
  let mut acc = 0
  let mut r = 0
  while r < reps {
    acc = acc + checksum(@utf8.encode(@lib.encode(Bytes::from_array(src)))[:])
    r = r + 1
  }
  acc
}

///|
/// **只解码**基准：`reps` 次 `@lib.decode`，回传解码结果校验和。
///
/// 输入是**被测侧自己编出来的**合法 base64（`det_bytes` → encode），
/// 与 `bench_roundtrip` 里 decode 用同一份输入，故两者可相减。
#export_name("bench_decode_only")
pub fn bench_decode_only(n : Int, seed : Int, reps : Int) -> Int {
  let encoded = @utf8.encode(@lib.encode(Bytes::from_array(det_bytes(n, seed))))
  let mut acc = 0
  let mut r = 0
  while r < reps {
    acc = acc + checksum(@lib.decode(encoded[:]).unwrap())
    r = r + 1
  }
  acc
}
