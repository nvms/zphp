<?php
// var_dump and print_r show a lazy object as php does: "lazy ghost" and
// "lazy proxy", typed properties not yet initialized as uninitialized, an
// initialized proxy as its instance; touching an undeclared property
// initializes the object
class C { public int $a; public $b = 5; private ?string $c = null; public function __construct() { $this->a = 1; } }
$r = new ReflectionClass(C::class);
$g = $r->newLazyGhost(function ($o) { $o->__construct(); });
var_dump($g);
$r->getProperty('b')->setRawValueWithoutLazyInitialization($g, 7);
var_dump($g);

print_r($g); echo "\n";
var_dump((array)$g);
$p = $r->newLazyProxy(function ($o) { return new C; });
var_dump($p);
$p->a;
var_dump($p);

print_r($p); echo "\n";
$g->a;
var_dump($g);
var_export($p); echo "\n";
#[AllowDynamicProperties]
class D { public int $a; public function __construct() { $this->a = 1; } }
$rd = new ReflectionClass(D::class);
$g2 = $rd->newLazyGhost(function ($o) { echo "init\n"; $o->__construct(); });
var_dump(@$g2->dynamic);
var_dump($rd->isUninitializedLazyObject($g2));
$g3 = $rd->newLazyGhost(function ($o) { echo "init\n"; $o->__construct(); });
$g3->other = 5;
var_dump($g3);
