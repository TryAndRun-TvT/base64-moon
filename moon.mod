// MoonBit 模块配置文件
// 参考: https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/module.html

name = "TryAndRun-TvT/base64-moon"

version = "0.1.0"

readme = "README.md"

repository = "https://cnb.cool/tryandrun/moonbit_dev/base64-moon"

license = "Apache-2.0"

keywords = [ "base64", "encoding" ]

// 默认/主推后端 = 实际分发形态

preferred_target = "wasm-gc"

// 显式声明实际支持的后端（native 需系统 C 编译器，当前不纳入）

supported_targets = "+wasm-gc"

description = "Base64 encoder/decoder written in MoonBit"
