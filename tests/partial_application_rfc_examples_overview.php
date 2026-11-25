<?php

require __DIR__ . '/partial_application_rfc_examples.inc';

function foo(int $a, int $b, int $c, int $d): int
{
    return $a + $b + $c + $d;
}

$tests = [
    'Test 1' => [
        foo(1, ?, 3, 4),
        static fn(int $b): int => foo(1, $b, 3, 4),
    ],
    'Test 2' => [
        foo(1, ?, 3, ?),
        static fn(int $b, int $d): int => foo(1, $b, 3, $d),
    ],
    'Test 3' => [
        foo(1, ...),
        static fn(int $b, int $c, int $d): int => foo(1, $b, $c, $d),
    ],
    'Test 4' => [
        foo(1, 2, ...),
        static fn(int $c, int $d): int => foo(1, 2, $c, $d),
    ],
    'Test 5' => [
        foo(1, ?, 3, ...),
        static fn(int $b, int $d): int => foo(1, $b, 3, $d),
    ],
];

check_equivalence($tests);

?>
