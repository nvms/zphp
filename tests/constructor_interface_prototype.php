<?php
// a constructor is checked against the one an interface of its parents
// declares, whether the parent declares one itself or not
interface I { function __construct(int $a); }
abstract class A implements I {}
class Ok extends A { function __construct(int $a, $b = null) { echo "ok $a\n"; } }
new Ok(1);
class B implements I { function __construct(int $a) {} }
class Ok2 extends B { function __construct(int|string $a) { echo "ok2\n"; } }
new Ok2("x");
ini_set("fatal_error_backtraces", "0");
eval("class Bad extends B { function __construct() {} }");
