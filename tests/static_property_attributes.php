<?php
// attributes on static properties reach reflection
#[Attribute] class A { function __construct(public $v = 0) {} }
class C { #[A(1)] public static $s; #[A(2)] public $p; public function __construct(#[A(3)] public $q = 0) {} public $h { #[A(4)] get => 1; } }
foreach (["s", "p", "q", "h"] as $n) { $r = new ReflectionProperty("C", $n); foreach ($r->getAttributes() as $a) var_dump($a->getName(), $a->getArguments()); }
