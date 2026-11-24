<?php
// php 8.6's new argument checks and defaults in ext/standard
function attempt(callable $f): void {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
// form feed is trimmed by default
var_dump(trim("\f\t x \f"), ltrim("\fa"), rtrim("a\f"), chop("b\f\n"));
var_dump(trim("\fa\f", " "));
attempt(fn() => array_change_key_case(['A' => 1], 2));
attempt(fn() => array_change_key_case(['A' => 1], -1));
attempt(fn() => array_change_key_case(['a' => 1], CASE_UPPER));
var_dump(ARRAY_FILTER_USE_VALUE);
attempt(fn() => array_filter([1, 0, 2], null, 3));
attempt(fn() => array_filter([], fn() => true, -1));
attempt(fn() => array_filter([1, 0, 2], fn($v) => $v, ARRAY_FILTER_USE_VALUE));
attempt(fn() => pathinfo('/a/b.c', 0));
attempt(fn() => pathinfo('/a/b.c', 16));
attempt(fn() => pathinfo('/a/b.c', PATHINFO_BASENAME | PATHINFO_EXTENSION));
attempt(fn() => pathinfo('/a/b.c', PATHINFO_FILENAME));
attempt(fn() => scandir(__DIR__, 3));
attempt(fn() => scandir(__DIR__, -1));
attempt(fn() => linkinfo(''));
attempt(fn() => sleep(-1));
attempt(fn() => sleep(PHP_INT_MAX));
attempt(fn() => usleep(4294967296));
attempt(fn() => explode('', 'abc'));
// clamp()
attempt(fn() => clamp(5, 1, 10));
attempt(fn() => clamp(-5, 1, 10));
attempt(fn() => clamp(50, 1, 10));
attempt(fn() => clamp(2.5, 1, 2));
attempt(fn() => clamp("b", "a", "c"));
attempt(fn() => clamp("z", "a", "c"));
attempt(fn() => clamp(1, 5, 1));
attempt(fn() => clamp(1, NAN, 2));
attempt(fn() => clamp(1, 0, NAN));
attempt(fn() => clamp(NAN, 0, 2));
attempt(fn() => clamp(null, 0, 2));
attempt(fn() => clamp([1], 0, 2));
attempt(fn() => clamp(new DateTime('2020-01-01'), new DateTime('2021-01-01'), new DateTime('2022-01-01')));
attempt(fn() => clamp(1, 2));
attempt(fn() => clamp(value: 3, max: 2, min: 1));
