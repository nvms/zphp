<?php
// php 8.6's gmp: arguments that must fit an unsigned long, NUL bytes in
// integer strings, gmp_prevprime() and gmp_powm_sec()
function attempt(callable $f): void {
    try {
        $r = $f();
        echo is_object($r) ? 'GMP(' . gmp_strval($r) . ')' : var_export($r, true), "\n";
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
attempt(fn() => gmp_fact(20));
attempt(fn() => gmp_fact(-1));
attempt(fn() => gmp_fact(gmp_pow(2, 70)));
attempt(fn() => gmp_binomial(10, 3));
attempt(fn() => gmp_binomial(-10, 3));
attempt(fn() => gmp_binomial(10, -1));
attempt(fn() => gmp_pow(3, 40));
attempt(fn() => gmp_pow(3, -1));
attempt(fn() => gmp_root(1000, 3));
attempt(fn() => gmp_root(1000, 0));
attempt(fn() => gmp_root(-1000, 2));
attempt(fn() => gmp_root(-1000, 3));
attempt(fn() => gmp_powm(3, 4, 5));
attempt(fn() => gmp_powm(3, 4, 0));
attempt(fn() => gmp_powm(3, -4, 5));
attempt(fn() => gmp_init(5) + "1\x00");
attempt(fn() => gmp_init(5) << gmp_pow(2, 64));
attempt(fn() => gmp_init(5) << gmp_init(-1));
attempt(fn() => gmp_init(5) ** gmp_init(3));
attempt(fn() => gmp_init(5) << 2.5);
attempt(fn() => gmp_init(5) ** -2);
attempt(fn() => gmp_fact("abc"));
attempt(fn() => gmp_fact([]));
if (function_exists('gmp_prevprime')) {
    attempt(fn() => gmp_prevprime(100));
    attempt(fn() => gmp_prevprime(3));
    attempt(fn() => gmp_prevprime(2));
    $sure = null;
    attempt(function () use (&$sure) { return gmp_prevprime(gmp_pow(10, 30), $sure); });
    var_dump($sure);
    gmp_prevprime(1000, $sure);
    var_dump($sure);
}
if (function_exists('gmp_powm_sec')) {
    attempt(fn() => gmp_powm_sec(3, 4, 7));
    attempt(fn() => gmp_powm_sec(3, 0, 7));
    attempt(fn() => gmp_powm_sec(3, 4, 8));
    attempt(fn() => gmp_powm_sec(3, 4, 0));
}
