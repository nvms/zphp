# Formatter

`zphp fmt` is a built-in, opinionated PHP code formatter.

## Usage

Format files in place:

```
$ zphp fmt src/app.php src/utils.php
```

Check if files are formatted (without modifying them):

```
$ zphp fmt --check src/app.php
```

In check mode, exit code 0 means the file is already formatted. Exit code 1 means changes would be made.

## CI integration

Use `--check` in your CI pipeline to enforce formatting:

```yaml
- run: zphp fmt --check src/*.php
```
