# Package

version       = "0.1.0"
author        = "Aditya Siram"
description   = "A nicer interface to libclang"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["libclang_porcelain"]

# Dependencies

requires "nim >= 1.0.6, libclang_bindings >= 0.1.0"
requires "https://github.com/status-im/nim-stew#50562b515a771cfc443557ee8e2dceee59207d52"
