# zphp

a zig-based PHP runtime. what bun is to node, zphp is to PHP.

you are the sole maintainer. read `ARCHITECTURE.md` for implementation details per subsystem. read `~/code/vigil/learnings.md` before technology decisions (don't commit/push to vigil repo).

## workflow

session start: `./audit`, `gh issue list` (be skeptical of issues)
session end: audit again, commit, push, update CLAUDE.md/ARCHITECTURE.md if needed

## standards

zig 0.15.x. `zig build test` must pass before pushing. short lowercase commits, no co-author. no emojis. casual comments only when code can't speak for itself. `gh` CLI for GitHub ops.

## known limitations

- arrays: reference semantics, not copy-on-write
- `global $var`: copies from frame 0, no write-back
- `require`: isolated scope (functions/classes global, variables don't leak)
- type hints: parsed, not enforced. heredoc/nowdoc: not supported
- `strtotime`: YYYY-MM-DD and relative only, UTC
- trait conflict resolution (`insteadof`/`as`): not implemented

## gotchas

**runtime errors**: use `throwBuiltinException` + `continue` for catchable errors, NOT `return error.RuntimeError` (bypasses PHP exception handlers, causes hangs in try/catch). pattern: `if (try self.throwBuiltinException("Error", msg)) continue; return error.RuntimeError;`

**generators**: yield/generator_return opcodes must `return` from runLoop, not `continue` (continue re-enters the loop instead of exiting to the caller)

**catch clauses**: must use `parseQualifiedName()` for types - `\Exception` starts with backslash, not identifier

**visibility**: `findPropertyVisibility`/`findMethodVisibility` return the defining class, not just visibility level. private checks against defining class, not object's runtime class

**stdlib conflicts**: functions registered later in registry.zig overwrite earlier ones. check existing stubs before adding implementations

**zig 0.15.x**: no `std.io.getStdOut()` (use `std.posix.write`). `std.ArrayList(T)` is unmanaged. `const` in structs after all fields. `link_libc = true` required for C libs. `std.http.Client` uses vtable-based Writer in 0.15 - use curl via `std.process.Child.run` for HTTP instead.

## CLI

- `zphp run <file>` - execute PHP file
- `zphp serve <file> [--port N] [--workers N]` - HTTP server with pre-compiled bytecode, VM pooling, keep-alive, static files, ETag/304
- `zphp test [file]` - test runner with assertion functions, test discovery, TUI output
- `zphp install` - install packages from composer.json, write zphp.lock
- `zphp add <pkg>` / `zphp remove <pkg>` - manage dependencies
- `zphp packages` - list installed packages

## CI

6 jobs: `zig build test` (ubuntu + macos), serve integration (`tests/serve_test`, 26 assertions), test runner (`tests/test_runner_test`, 15 assertions), packages (`tests/pkg_test`, 10 assertions), PHP compat (`tests/run`, 66 files)

## roadmap

next: `zphp fmt`, gzip compression for serve static files, `SplStack`/`ArrayObject`, fibers, WebSocket support for serve (design toward event-loop-per-worker for long-lived connections - don't assume all connections are short-lived request/response)

## distribution

GitHub releases with prebuilt binaries. bump version in build.zig.zon, commit with version number, tag, push.

## user commands

- "hone" or starting a conversation - run audit, check issues, assess and refine
- "hone \<area\>" - focus on a specific area
- "retire" - archive the project (see ARCHITECTURE.md for steps)
