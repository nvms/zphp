<?php
// a nullsafe chain short-circuits a static call made on its result, and one
// inside an argument or an index ends there
class Foo { function null() { var_dump("Foo::null()"); return null; } function self() { var_dump("Foo::self()"); return $this; } static function baz() { return "baz"; } }
var_dump(null?->bar()::baz());
$foo = new Foo;
var_dump($foo->null()?->bar()::baz());
var_dump($foo?->self()::baz());
var_dump($foo->self(null?->bar())->null());
try { var_dump($foo?->self()[null?->bar()]); } catch (Throwable $e) { var_dump($e->getMessage()); }
var_dump(strlen(null?->x ?? "abc"));
