<?php

require __DIR__ . '/partial_application_rfc_examples.inc';

class Foo {
    public function __call($method, $args) {
        printf("%s::%s\n", __CLASS__, $method);
        print_r($args);
    }
}

$f = new Foo();

check_equivalence([
    'Test 1' => [
        $f->method(?, ?),
        (function ($f) {
            return fn(mixed $arguments0, mixed $arguments1) => $f->method($arguments0, $arguments1);
        })($f)->bindTo($f),
    ],
]);

try {
    $f->method(?, ?)(a: 1, b: 2);
} catch (Error $e) {
    echo $e::class, ": ", $e->getMessage(), "\n";
}

?>
