<?php
// a partial application is no attribute argument
#[Attribute]
class A { function __construct(...$args) {} }
#[A(1, x: ?)]
function f() {}
echo "unreachable\n";
