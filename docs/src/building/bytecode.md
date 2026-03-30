# Bytecode Compilation

`zphp build` compiles a PHP file to bytecode ahead of time. The output is a `.zphpc` file that can be executed directly, skipping the parsing and compilation step at runtime.

## Usage

```
$ zphp build app.php
```

This produces `app.zphpc` in the same directory. Run it with:

```
$ zphp run app.zphpc
```

## When to use this

For most use cases, `zphp run` and `zphp serve` handle compilation transparently and you don't need to think about it. `zphp serve` compiles your entry point once at startup and reuses the bytecode across all workers and requests.

Pre-compiling to `.zphpc` is useful when you want to:
- Ship bytecode without source files
- Eliminate any startup compilation overhead in scripting contexts
- Verify that a file compiles successfully without running it

## See also

For shipping your PHP application as a single self-contained binary, see [Standalone Executables](./standalone.md).
