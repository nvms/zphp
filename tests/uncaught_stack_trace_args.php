<?php
// regression: stack trace shows Class->method() vs Class::method() based on
// static-ness, includes args formatted like PHP (Array for arrays,
// Object(ClassName) for objects, 'string' truncated at 15 chars, scalars
// literal, NULL/true/false bare), and resolves the caller-frame's actual
// source for file:line per entry (not vm.file_path everywhere)
class Foo {
    public function bar($s, $n, $arr, $obj, $b, $nu) {
        $this->baz($s, $arr);
    }
    public function baz($s, $arr) {
        Foo::flap();
    }
    public static function flap() {
        undefined_thing();
    }
}
function go(Foo $f, $long_str) {
    $f->bar($long_str, 42, ['a','b'], new stdClass(), true, null);
}
go(new Foo(), "this is a string longer than fifteen characters");
