<?php
// PHP keeps `private` properties per declaring class - parent's `private $foo`
// and child's `private $foo` are separate storage slots. previously zphp
// flattened them into one slot, which broke real Symfony code where a
// child declares `private readonly $foo` while a parent has its own
// `private $foo`; the parent's write would trip the child's readonly
// init-once gate. now: separate slots per declaring class, scope-aware
// reads/writes pick the right slot, set_prop_default patches the
// (name AND declaring_class)-matched slot, slot_layout records
// declaring_class + is_private per slot.

echo "== parent and child with same-named private ==\n";
class A {
    private string $name = '';
    public function __construct() { $this->name = 'A-init'; }
    public function aName(): string { return $this->name; }
}
class B extends A {
    private readonly string $name;
    public function __construct() {
        parent::__construct();
        $this->name = 'B-init';
    }
    public function bName(): string { return $this->name; }
}
$b = new B;
echo "A view: ", $b->aName(), "\n";
echo "B view: ", $b->bName(), "\n";

echo "== separate state, both writable in own scope ==\n";
class P { private int $count = 0; public function bump(): void { $this->count++; } public function get(): int { return $this->count; } }
class Q extends P { private int $count = 100; public function bumpQ(): void { $this->count++; } public function getQ(): int { return $this->count; } }
$q = new Q;
$q->bump(); $q->bump(); $q->bumpQ();
echo "P count: ", $q->get(), "\n";
echo "Q count: ", $q->getQ(), "\n";

echo "== readonly init from parent then child, both succeed (no false re-write) ==\n";
class X { private readonly string $tag; public function __construct() { $this->tag = 'X-tag'; } public function xtag(): string { return $this->tag; } }
class Y extends X { private readonly string $tag; public function __construct() { parent::__construct(); $this->tag = 'Y-tag'; } public function ytag(): string { return $this->tag; } }
$y = new Y;
echo "X tag: ", $y->xtag(), "\n";
echo "Y tag: ", $y->ytag(), "\n";

echo "== readonly re-write after init is rejected (tightened check) ==\n";
class R { private readonly int $val; public function __construct() { $this->val = 1; } public function rewrite(): void { $this->val = 2; } }
$r = new R;
try { $r->rewrite(); echo "ERROR: no throw\n"; } catch (Error $e) { echo "caught: ", $e->getMessage(), "\n"; }
