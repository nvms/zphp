<?php
// arguments php's stubs mark #[\SensitiveParameter] are hidden in the
// stack traces of exceptions internal functions throw
function show(callable $f) {
    try {
        $f();
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
        $frame = $e->getTrace()[0];
        echo $frame["function"], " ", implode(", ", array_map(fn($a) => is_object($a) ? get_class($a) : var_export($a, true), $frame["args"] ?? [])), "\n";
        echo preg_replace('/^#\d+ \S+\(\d+\): /m', '', $e->getTraceAsString()), "\n";
    }
}
show(fn() => hash_equals('foo', null));
show(fn() => hash_hmac('foo', 'bar', 'baz'));
show(fn() => hash_pbkdf2('nope', 'secret password', 'salt', 1));
show(fn() => hash_hkdf('nope', 'ikm'));
show(fn() => hash_init('md5', HASH_HMAC));
show(fn() => password_hash('secret', 'nope'));
show(fn() => hash('nope', 'not sensitive'));
