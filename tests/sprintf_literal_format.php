<?php
// php compiles sprintf() with a literal format of only %s, %d and %% into
// string casts: every value is evaluated first, the first failing conversion
// stops the rest, and no sprintf frame shows in the trace

namespace {
    class Tag
    {
        public function __construct(public string $name) { echo "made {$this->name}\n"; }
        public function __toString(): string { echo "rendered {$this->name}\n"; return "<{$this->name}>"; }
    }
    class Opaque
    {
        public function __construct() { echo "made opaque\n"; }
    }

    $user = 'ada';
    $id = 1815;
    echo sprintf('%s#%d', $user, $id), "\n";
    echo sprintf('/users/%d/posts/%s', '42', 'hello-world'), "\n";
    echo sprintf('100%% of %s', 'tests'), "|", sprintf('%%'), "|", sprintf(''), "|", sprintf('plain'), "\n";
    echo sprintf("%s\t%d\n", 'tab', 3.99);
    echo sprintf('%s %s %s %s', true, false, null, 1.5), "|\n";
    echo sprintf('%d %d %d', '12abc', ' 7', "\v8"), "\n";
    echo SPRINTF('%s', 'case'), \sprintf('-%s', 'qualified'), "\n";
    echo sprintf('%s and %s', new Tag('a'), new Tag('b')), "\n";

    try {
        echo sprintf('%s|%s|%s', new Opaque(), new Tag('never'), new Opaque()), "\n";
    } catch (\Error $e) {
        echo $e, "\n";
    }

    try {
        echo sprintf('%d-%s', new Opaque(), []), "\n";
    } catch (\Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }

    set_error_handler(function (int $no, string $msg): bool {
        throw new \ErrorException($msg, 0, $no);
    });
    try {
        echo sprintf('%s-%s', [], new Tag('skipped')), "\n";
    } catch (\ErrorException $e) {
        echo $e, "\n";
    }
    restore_error_handler();

    echo sprintf('%d', 1e20), "\n";
    $n = acos(8);
    echo sprintf('%s', $n), "\n";
    echo sprintf('%s|%s|%s', 0.1 + 0.2, 1e15, -0.0), "\n";
    echo sprintf('%s|%s|%s', 0.0036288879892346, 324582.49435, 1 / 3), "\n";
}

namespace App {
    // unqualified in a namespace, the call is resolved at runtime and shows in traces
    try {
        echo sprintf('%s', new \Opaque()), "\n";
    } catch (\Error $e) {
        echo $e, "\n";
    }
    try {
        echo \sprintf('%s', new \Opaque()), "\n";
    } catch (\Error $e) {
        echo $e, "\n";
    }
}
