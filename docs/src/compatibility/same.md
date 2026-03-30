# What Works the Same

zphp aims to run standard PHP code as-is. The following all work the way you'd expect from PHP:

- **Types**: strings, integers, floats, booleans, arrays, null, objects
- **Control flow**: if/else, switch, match, for, foreach, while, do-while
- **Functions**: named functions, closures, arrow functions, default parameters, variadic arguments, named arguments, pass-by-reference
- **Classes**: inheritance, interfaces, traits, abstract classes, static methods and properties, visibility modifiers, constructors, magic methods (`__construct`, `__get`, `__set`, `__call`, `__callStatic`, `__toString`, `__invoke`, `__clone`, `__isset`, `__unset`)
- **Namespaces**: `use` statements, fully qualified names, aliases
- **Exceptions**: try/catch/finally, custom exception classes, exception chaining
- **Generators**: yield, yield from, generator return values
- **Enums**: basic and backed enums, enum methods
- **Type hints**: parameter types, return types, nullable types, union types
- **String interpolation**: `"Hello, $name"` and `"Hello, {$obj->name}"`
- **Arrays**: both sequential and associative, nested arrays, array destructuring
- **Superglobals**: `$_SERVER`, `$_GET`, `$_POST`, `$_COOKIE`, `$_FILES` (in serve mode)
- **Standard library**: string functions, array functions, math functions, JSON, date/time, file I/O, regex (PCRE2), PDO (SQLite, MySQL, PostgreSQL)

## Test suite

zphp is validated against PHP 8.4 with 167 compatibility tests and 75 multi-file example projects. Each test runs the same PHP code in both zphp and PHP 8.4, comparing output exactly. The test suite runs on every commit.
