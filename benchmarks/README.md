# benchmarks

## fmt

Formats `sample.php` (416 lines) with each tool, reports best of 10 runs.

```
./benchmarks/fmt
```

Requires `zig build` first. Installs prettier locally if node/npm is available. Skips php-cs-fixer if php is not installed.

### Results (Apple M4)

```
  zphp fmt                          5 ms
  prettier @prettier/plugin-php     91 ms
  php-cs-fixer                 skipped (no php)
```
