<?php
// a class, trait or function declared inside an if or a function brings the
// methods and types of the declaration that ran
if (true) { class A { function f() { return 1; } } } else { class A { function f() { return 2; } } }
echo (new A)->f(), "\n";
if (true) { trait T { function f() { return 1; } } } else { trait T { function f() { return 2; } } }
class B { use T; }
echo (new B)->f(), "\n";
if (false) { trait T2 { function f(): ?int { return 1; } } } else { trait T2 { function f(): int { return 2; } } }
class B2 { use T2; }
echo (new B2)->f(), " ", (new ReflectionMethod("B2", "f"))->getReturnType(), "\n";

interface I { public function f(): ReflectionClass; }
if (!class_exists("Nope")) {
    trait TR { public function f(): ReflectionClass { return new ReflectionClass("I"); } }
} else {
    trait TR { public function f(): ReflectionClass|null { return null; } }
}
class C implements I { use TR; }
echo get_class((new C)->f()), "\n";

if (true) { function g(int $a): int { return $a; } } else { function g(string $a): string { return $a; } }
var_dump(g("5"));
echo (new ReflectionFunction("g"))->getReturnType(), "\n";

function make() {
    class Inner {
        const V = [1, 2];
        public int $p = 3;
        public $h { get => "hook"; }
        function v() { return self::V; }
    }
}
make();
$i = new Inner;
var_dump($i->v(), $i->p, $i->h);
if (false) { class NotDeclared { function n() {} } }
var_dump(class_exists("NotDeclared", false));
