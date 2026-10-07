///|
/// 解码内核（**零分配**：`BytesView` 进 / `FixedArray[Byte]` 出）。
///
/// 与编码侧的关键差别：解码入参**绝不能**是 `String`。
/// 理由（[S1 §5.3](docs/01-规格/S1-rust-base64-移植可行性分析.md)）：
/// `String` 是 UTF-16，按 code unit 取字节等于先把字节塞进 UTF-8 再取出——语义与性能双输。
/// 这也是 [S2 §2.4](docs/01-规格/S2-现状基线与迁移缺口.md) 把「`decode` 收 `String`」
/// 判为**签名错误**（而非优化空间）的原因。
///
/// 本层把 crate 的 `decode.rs` + `decode_suffix.rs` 拆成三个函数：
/// `decoded_len_estimate`（上界）/ `decode_complete_quads`（完整 4 元组）/
/// `decode_suffix`（尾巴，判据 2/3/4 的唯一落点）。
///
/// **错误优先级照 crate 实测，不照直觉**（汇总见 [S5 §3](docs/01-规格/S5-实施裁决与M1落地.md)）。
///
/// **热循环形态 = 显式 4 条查表 + 合并判错 + 冷路径定位**（[S10](docs/01-规格/S10-去内循环落地与端到端对照.md)）：
/// [S9 §4](docs/01-规格/S9-M5语义矩阵与32位装载裁决.md) 实测「`for k` 内循环本身就是成本」——
/// 去掉它、把 4 个 morsel 摆成显式 `let`，热循环段从 0.71× 降到 **0.65×**（再快约 8%）。
/// 判错从「逐符号 4 个分支」合并成一个 `acc < 0`（见 `locate_invalid_byte` 的等价性说明），
/// offset 精度靠**冷路径**（出错才走）保证。

///|
/// 估算解码后的字节数上界（用于预分配输出缓冲）。
///
/// 对齐 crate 的 `GeneralPurposeEstimate::new`：`(len / 4 + (len % 4 > 0)) * 3`。
/// 上界而非精确值——最多多算 2 字节，但保证「一定够」。
/// 实测对照：0→0、1..4→3、5..8→6、9→9。
pub fn decoded_len_estimate(input_len : Int) -> Int {
  let rem = input_len % 4
  (input_len / 4 + (if rem > 0 { 1 } else { 0 })) * 3
}

///|
/// 解码内核：把 `input` 解到 `out`，返回**实际写入的字节数**。
///
/// 对齐 crate 的 `decode_slice(input, &mut [u8]) -> Result<usize, DecodeSliceError>`。
///
/// 本函数是 [S2 §2.1](docs/01-规格/S2-现状基线与迁移缺口.md) 四条判据的**唯一落点**：
///   1. 混入非字母表字节 → `InvalidByte(offset, byte)`；
///   2. 末尾有效符号数 `% 4 == 1` → `InvalidLength(输入总长)`；
///   3. 末符号低位冗余位非零 → `InvalidLastSymbol(offset, byte)`；
///   4. padding 数量 / 位置不合 `padding_mode` → `InvalidPadding` / `InvalidByte`。
///
/// **执行次序照 crate（照抄，别自行「理顺」）**：
/// ① `rem == 1` 的尾字节便利检查（仅当尾字节非法且非 padding）；
/// ② 完整 4 元组逐组解码，**含位置 0/1 的 padding 检查**；
/// ③ 输出缓冲够不够；
/// ④ 尾巴交给 `decode_suffix`（判据 2/3/4）。
///
/// ②与③的先后**不能换**：换成先查缓冲，`decode_slice("=Zm9v", 1 字节)` 会在
/// 「缓冲不足」还是「位置 0 是 padding」之间给出与 crate 相反的错误。
pub fn decode_into(
  engine : Engine,
  input : BytesView,
  out : FixedArray[Byte],
) -> Result[Int, DecodeSliceError] {
  let n = input.length()
  let rem = n % 4
  let table = engine.decode_table
  let padding = engine.alphabet.padding
  // ① 尾部 1 字节的便利检查：`"Zm9vYmFy\n"` 报 InvalidByte(8, 0x0A) 而不是 InvalidLength。
  //    刻意排除 padding 字节——它可能属于从前面延伸过来的 padding，由 ② 或 ④ 处理。
  if rem == 1 {
    let last = input[n - 1]
    if last != padding && table[last.to_int()] == -1 {
      return Err(DecodeFailed(InvalidByte(n - 1, last)))
    }
  }
  // ② 完整且非末尾的 4 元组：`n - rem` 起是尾巴；rem == 0 时末尾那组也要留给
  //    decode_suffix（它可能带 padding，见 `"Zm9vYmFy="`）。
  //
  //    **完整 4 元组里的非字母表字节（含位置 0/1 的 padding）在这里就报**——
  //    这条**先于**缓冲检查。crate 的实测行为：`decode_slice("Zm9v!", 1 字节)`
  //    报 `InvalidByte(4, b'!')` 而不是 `OutputSliceTooSmall`。
  let quads_end = n - rem - (if rem == 0 && n > 0 { 4 } else { 0 })
  // ③ 缓冲够不够：**在解码任何一组之前**判。
  //
  //    次序是照 crate 的 `complete_quads_len` 复刻的，两条都实测过：
  //      · 先做 ①（rem==1 的尾字节便利检查），再判缓冲，再逐组解码——
  //        故 `Zm9v!`（1 字节缓冲）报 `InvalidByte(4, b'!')`，**不是** `OutputSliceTooSmall`。
  //      · 缓冲只看「完整 4 元组」要多少：`=Zm9v`（长度 4、整组、`quads_end = 0`）
  //        要 0 字节，于是 2 字节缓冲下它**不该**报缓冲不足，而应落到 ④ 报
  //        `InvalidByte(0, b'=')`。实测 crate：`=Zm9v` 带 2 字节缓冲 → `OutputSliceTooSmall`，
  //        带 3 字节 → `InvalidByte(0, b'=')`。差的那一字节就是 `Zm9v` 这一组。
  //
  //    即：**位置 0/1 的 padding 检查发生在完整组解码之中**，所以缓冲必须先够。
  //    把这条检查放错位置，`=Zm9v` 会在 2 / 3 字节缓冲下给出相反的答案。
  let complete_need = quads_end / 4 * 3
  if out.length() < complete_need {
    return Err(OutputSliceTooSmall)
  }
  let mut i = 0
  let mut o = 0
  while i < quads_end {
    let b0 = table[input[i].to_int()]
    let b1 = table[input[i + 1].to_int()]
    let b2 = table[input[i + 2].to_int()]
    let b3 = table[input[i + 3].to_int()]
    let acc = (b0 << 18) | (b1 << 12) | (b2 << 6) | b3
    if acc < 0 {
      return Err(locate_invalid_byte(table, input, i))
    }
    out[o] = ((acc >> 16) & 0xFF).to_byte()
    out[o + 1] = ((acc >> 8) & 0xFF).to_byte()
    out[o + 2] = (acc & 0xFF).to_byte()
    i += 4
    o += 3
  }
  // ④ 尾巴
  decode_suffix(table, padding, engine.config, input, i, o, out)
}

///|
/// 冷路径：在完整 4 元组内**定位第一个非法符号**，返回 `InvalidByte(绝对下标, 字节)`。
///
/// 为什么单独成函数（不在热循环里内联）：合并判错（`acc < 0`）本身不含「哪个符号错」，
/// 而要报精确 offset 就得重扫这 4 个下标。把它**外提**后，热路径只剩一个分支，
/// 实测（185 KB）**0.65× vs 逐符号判错的 0.68×** —— 内联的定位代码反而会拖慢热循环
/// （[S10 §3](docs/01-规格/S10-去内循环落地与端到端对照.md)）。
///
/// **`acc < 0` ⟺ 「四个 morsel 里至少一个为负」的等价性**（合并判错的前提）：
/// `acc = (b0<<18)|(b1<<12)|(b2<<6)|b3`，morsel ∈ {-1} ∪ [0, 63]。
/// MoonBit 的 `Int` 是 **31 位有效位 + 符号位**（见 `decode_suffix` 里 `UInt` 那条注释），
/// `-1` 的位模式是全 1；故任一 `b<0` 都会把 `acc` 的高位置 1（`acc<0`）。
/// 反向：全 `b ∈ [0,63]` 时 `acc = b0<<18 | …` 上界 `0xFFFFFF`（24 位），恒 ≥ 0。
/// **全部 65⁴ = 17 850 625 种组合穷举验证过**（复跑见 S10 §5），故等价。
fn locate_invalid_byte(
  table : FixedArray[Int],
  input : BytesView,
  start : Int,
) -> DecodeSliceError {
  for k = 0; k < 4; k = k + 1 {
    if table[input[start + k].to_int()] < 0 {
      return DecodeFailed(InvalidByte(start + k, input[start + k]))
    }
  }
  // 不可达：调用方只在 `acc < 0` 时进来，而 `acc < 0` 等价于「至少一个非法」。
  DecodeFailed(InvalidByte(start, input[start]))
}

///|
/// 后缀校验：一次回答「末尾 1~4 个符号是否合法」，返回**解码后总字节数**。
///
/// 单列的理由（[S1 §3.1](docs/01-规格/S1-rust-base64-移植可行性分析.md)）：
/// crate 的 `decode_suffix.rs` 有 170 行专写这一段，它是**最容易漏的一块**——
/// 四条判据里有三条（2 / 3 / 4）都落在这里，且组合很多
/// （4 错误 × 3 padding 模式 × 冗余位开关）。
///
/// 参数里的 `start` / `written` 是**绝对坐标**：`input[start..]` 才是尾巴，
/// `out[written..]` 才是可写区。错误 offset 一律用绝对下标。
pub fn decode_suffix(
  table : FixedArray[Int],
  padding : Byte,
  config : Config,
  input : BytesView,
  start : Int,
  written : Int,
  out : FixedArray[Byte],
) -> Result[Int, DecodeSliceError] {
  let n = input.length()
  let morsels : FixedArray[Int] = FixedArray::make(4, 0)
  let mut morsels_count = 0
  let mut padding_count = 0
  let mut first_padding_offset = 0
  let mut last_symbol = b'\x00'
  for idx = start; idx < n; idx = idx + 1 {
    let byte = input[idx]
    if byte == padding {
      // padding 出现在本 4 元组的位置 0 / 1：它前面只可能有 0~1 个有效符号，
      // 而一个字节至少要 2 个符号——故这是错，且报**这个 padding 自己的位置**。
      if idx - start < 2 {
        return Err(DecodeFailed(InvalidByte(idx, byte)))
      }
      if padding_count == 0 {
        first_padding_offset = idx
      }
      padding_count += 1
      continue
    }
    // padding 之后又出现非 padding 字节：报**第一个** padding 的位置。
    // 这条同时也是「多余 `=` 被静默吞掉」的堵口——`"Zm9vYg==="` 落到这里。
    if padding_count > 0 {
      return Err(DecodeFailed(InvalidByte(first_padding_offset, padding)))
    }
    last_symbol = byte
    let morsel = table[byte.to_int()]
    if morsel < 0 {
      return Err(DecodeFailed(InvalidByte(idx, byte)))
    }
    morsels[morsels_count] = morsel
    morsels_count += 1
  }
  // 判据 2：末尾只可能剩 1 个有效符号（RFC 4648 §3.5 禁止）。字段是输入总长。
  if n > 0 && morsels_count < 2 {
    return Err(DecodeFailed(InvalidLength(n)))
  }
  match config.padding_mode {
    Indifferent => ()
    RequireCanonical =>
      if (padding_count + morsels_count) % 4 != 0 {
        return Err(DecodeFailed(InvalidPadding))
      }
    RequireNone =>
      if padding_count > 0 {
        return Err(DecodeFailed(InvalidPadding))
      }
  }
  // 判据 3 + 尾字节写回：把 4 个 6 位值左对齐拼成一个「32 位无符号整数」，
  // 再看「本该无值的位」里有没有非零，最后逐字节取高位写出。
  //
  // **必须用 `UInt` 而不是 `Int`**：MoonBit 的 `Int` 是 31 位有效位 + 符号位，
  // 而 `packed` 的最高字节常常 ≥ 0x80（如 `-_8=` 的首字节 0xFB）。用 `Int` 装会
  // 直接把最高位当符号，于是 `>> 24` 抽出负数、`<< 8` 丢掉 0x80——实测表现为
  // `0xfb 0x7f`（应为 `0xfb 0xff`）。`UInt` 是 32 位无符号，与 crate 的 `u32` 对齐。
  let leftover_bytes = morsels_count * 6 / 8
  let mut packed : UInt = (morsels[0].reinterpret_as_uint() << 26) |
    (morsels[1].reinterpret_as_uint() << 20) |
    (morsels[2].reinterpret_as_uint() << 14) |
    (morsels[3].reinterpret_as_uint() << 8)
  // 「本该无值的位」= 有效字节之**外**的低位（有效位恒在高位）。
  // 即 crate 的 `!0u32 >> (leftover_bytes * 8)`：
  //   2 符号 → 1 字节 → 掩码 0x00FFFFFF
  //   3 符号 → 2 字节 → 掩码 0x0000FFFF
  //   4 符号 → 3 字节 → 掩码 0x00000000（没有冗余位）
  let mask : UInt = if leftover_bytes >= 4 {
    0U
  } else {
    0xFFFFFFFFU >> (leftover_bytes * 8)
  }
  if !config.decode_allow_trailing_bits && (packed & mask) != 0U {
    return Err(
      DecodeFailed(InvalidLastSymbol(start + morsels_count - 1, last_symbol)),
    )
  }
  let mut idx = written
  for k = 0; k < leftover_bytes; k = k + 1 {
    if idx >= out.length() {
      // 尾巴的输出装不下：这是**缓冲不足**，不是输入错——
      // 归到 `InvalidPadding` 会让调用方误以为数据有问题。
      return Err(OutputSliceTooSmall)
    }
    // 取**当前最高字节**再整体左移一字节——6 位值被摆在 32 位的高 24 位，
    // 故 `>> 24` 拿到的就是最左那个还没写过的字节。
    out[idx] = ((packed >> 24).reinterpret_as_int() & 0xFF).to_byte()
    idx += 1
    packed = packed << 8
  }
  Ok(idx)
}
