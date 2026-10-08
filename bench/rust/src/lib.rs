//! Rust 侧基准 —— 与 MoonBit harness **同签名、同语义**的对照实现。
//!
//! 【为什么也编到 wasm 而不是 native】对照的两侧必须在**同一个计时器与同一个
//! 执行模型**下度量（bench/README.md 口径 ②）。Rust native 与 wasm-gc 的
//! 内存模型、调用约定、JIT 都不同，native 数字与 MoonBit 数字**不同层**。
//! 故两侧都编 wasm，都由 Node 加载、由 Node 计时。
//!
//! 【口径要素 ①：数据在被测侧生成】`det()` 是 `b[i] = (i * 37 + 11 + seed) & 0xFF`
//! 的 Rust 复刻，与 MoonBit 侧 `det_bytes`、JS 侧 `detBytes` 逐字同式。
//! 输入不跨边界传，因而「比的是算法不是搬运」。
//!
//! 【口径要素 ④：防 DCE】所有出口回传校验和 / 长度累加值；`panic = "abort"`
//! 下不会被优化掉的唯一保险就是「结果被写进返回值」。

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;

/// 数据生成：与 MoonBit `det_bytes` / JS `detBytes` 同式的 Rust 复刻。
fn det(n: usize, seed: u8) -> Vec<u8> {
    (0..n)
        .map(|i| ((i * 37 + 11 + seed as usize) & 0xFF) as u8)
        .collect()
}

/// 字节校验和：与 MoonBit `checksum` / JS `checksum` 同式（`Int` 累加）。
fn checksum(b: &[u8]) -> i32 {
    b.iter().fold(0i32, |a, &x| a.wrapping_add(x as i32))
}

/// 往返校验（单次，不计时）：回传解码结果校验和，供跨实现逐位对账。
#[no_mangle]
pub extern "C" fn verify_roundtrip(n: usize, seed: u8) -> i32 {
    let src = det(n, seed);
    let enc = STANDARD.encode(&src);
    match STANDARD.decode(enc.as_bytes()) {
        Ok(d) if checksum(&d) == checksum(&src) => checksum(&d),
        _ => -1,
    }
}

/// 编码输出校验和（单次）：供跨实现比对编码串是否逐字节相同。
#[no_mangle]
pub extern "C" fn verify_encode(n: usize, seed: u8) -> i32 {
    checksum(STANDARD.encode(det(n, seed)).as_bytes())
}

/// 编码**内核**基准：`reps` 次 `STANDARD.encode_slice`（不物化 String）。
///
/// 与 MoonBit 侧 `bench_encode_slice` 同层：都调各自的零分配内核入口。
#[no_mangle]
pub extern "C" fn bench_encode_slice(n: usize, seed: u8, reps: usize) -> i32 {
    let src = det(n, seed);
    let mut out = vec![0u8; (n + 2) / 3 * 4];
    let mut acc = 0i32;
    for _ in 0..reps {
        match STANDARD.encode_slice(&src, &mut out) {
            Ok(len) => acc = acc.wrapping_add(len as i32),
            Err(_) => acc = acc.wrapping_sub(1),
        }
    }
    acc
}

/// 解码**内核**基准：`reps` 次 `STANDARD.decode_slice`（不物化 Vec）。
#[no_mangle]
pub extern "C" fn bench_decode_slice(n: usize, seed: u8, reps: usize) -> i32 {
    let enc = STANDARD.encode(det(n, seed));
    let mut out = vec![0u8; (enc.len() / 4 + 1) * 3];
    let mut acc = 0i32;
    for _ in 0..reps {
        match STANDARD.decode_slice(enc.as_bytes(), &mut out) {
            Ok(len) => acc = acc.wrapping_add(len as i32),
            Err(_) => acc = acc.wrapping_sub(1),
        }
    }
    acc
}

/// **往返**基准：`reps` 次 encode → decode，回传解码结果校验和。
///
/// 这是跨实现对比的**统一口径**（各侧都只导出往返）。
#[no_mangle]
pub extern "C" fn bench_roundtrip(n: usize, seed: u8, reps: usize) -> i32 {
    let src = det(n, seed);
    let mut acc = 0i32;
    for _ in 0..reps {
        let enc = STANDARD.encode(&src);
        let dec = STANDARD.decode(enc.as_bytes()).expect("roundtrip");
        acc = acc.wrapping_add(checksum(&dec));
    }
    acc
}

// ── 分向（encode-only / decode-only）基准 ─────────────────────────────────────

/// **只编码**：`reps` 次 `STANDARD.encode`（含 `String` 物化），回传编码串校验和。
///
/// 与 `bench_roundtrip` 同层，只是不含 decode —— 与 MoonBit 侧 `bench_encode_only` 对齐。
/// （曾另有一个与它**逐字相同**的 `bench_encode_e2e`，两侧都不再导出：语义重复、无调用方。）
#[no_mangle]
pub extern "C" fn bench_encode_only(n: usize, seed: u8, reps: usize) -> i32 {
    let src = det(n, seed);
    let mut acc = 0i32;
    for _ in 0..reps {
        acc = acc.wrapping_add(checksum(STANDARD.encode(&src).as_bytes()));
    }
    acc
}

/// **只解码**：`reps` 次 `STANDARD.decode`，回传解码结果校验和。
///
/// 输入是被测侧自己编出的合法 base64，与 `bench_roundtrip` 的 decode 同一份输入。
#[no_mangle]
pub extern "C" fn bench_decode_only(n: usize, seed: u8, reps: usize) -> i32 {
    let enc = STANDARD.encode(det(n, seed));
    let mut acc = 0i32;
    for _ in 0..reps {
        let dec = STANDARD.decode(enc.as_bytes()).expect("decode_only");
        acc = acc.wrapping_add(checksum(&dec));
    }
    acc
}
