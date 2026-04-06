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
- **Attributes**: `#[Attribute]` syntax on classes, methods, properties, and parameters, with full reflection support (`getAttributes()`, `getName()`, `getArguments()`, `newInstance()`)
- **Type hints**: parameter types, return types, nullable types, union types
- **String interpolation**: `"Hello, $name"` and `"Hello, {$obj->name}"`
- **Arrays**: both sequential and associative, nested arrays, array destructuring
- **Superglobals**: `$_SERVER`, `$_GET`, `$_POST`, `$_COOKIE`, `$_FILES`, `$_ENV`, `$_REQUEST`, `$_SESSION` (in serve mode)
- **Fibers**: `Fiber`, `Fiber::start`, `Fiber::resume`, `Fiber::suspend`, `Fiber::getReturn`, `Fiber::isRunning`, `Fiber::isTerminated`, `Fiber::isSuspended`, `Fiber::isStarted`, `Fiber::getCurrent`
- **SPL**: `SplStack`, `SplQueue`, `SplDoublyLinkedList`, `SplPriorityQueue`, `SplFixedArray`, `SplMinHeap`, `SplMaxHeap`, `SplObjectStorage`, `ArrayObject`, `ArrayIterator`, `WeakMap`
- **Sessions**: `session_start`, `session_destroy`, `session_id`, `$_SESSION`
- **HTTP functions**: `header()`, `header_remove()`, `http_response_code()`, `setcookie()`, `headers_sent()`, `headers_list()`
- **Output buffering**: `ob_start`, `ob_get_clean`, `ob_end_clean`, `ob_get_contents`, `ob_get_level`
- **cURL**: `curl_init`, `curl_setopt`, `curl_setopt_array`, `curl_exec`, `curl_close`, `curl_error`, `curl_errno`, `curl_getinfo`, `curl_reset`, `curl_version`, with all common `CURLOPT_*` and `CURLINFO_*` constants
- **Standard library**: string functions, array functions, math functions, JSON, date/time, file I/O, regex (PCRE2), PDO (SQLite, MySQL, PostgreSQL)

## Test suite

zphp is validated against PHP 8.4 with 190 compatibility tests and 87 multi-file example projects. Each test runs the same PHP code in both zphp and PHP 8.4, comparing output exactly. A Laravel application (7 harness tests covering Eloquent, Blade, validation, JSON API, middleware, and error handling) is also tested against both runtimes. Standalone executable compilation is verified with 12 additional tests. The test suite runs on every commit.
