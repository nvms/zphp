<?php
// regression: a readonly property is initialized exactly once. after it holds
// a value, every later write is rejected - including writes from inside the
// declaring class (e.g. $this->prop++ in a method). zphp previously allowed
// re-writes as long as they came from the declaring class scope.

class Counter {
    public readonly int $count;
    public function __construct() { $this->count = 0; }
    public function bumpViaIncrement(): string {
        try { $this->count++; return 'modified'; }
        catch (\Error $e) { return 'blocked'; }
    }
    public function bumpViaAssign(): string {
        try { $this->count = 99; return 'modified'; }
        catch (\Error $e) { return 'blocked'; }
    }
    public function bumpViaCompound(): string {
        try { $this->count += 5; return 'modified'; }
        catch (\Error $e) { return 'blocked'; }
    }
}

$c = new Counter;
echo $c->count, "\n";                 // 0
echo $c->bumpViaIncrement(), "\n";    // blocked
echo $c->bumpViaAssign(), "\n";       // blocked
echo $c->bumpViaCompound(), "\n";     // blocked
echo $c->count, "\n";                 // 0 (unchanged)

// promoted readonly: same rule
class Point {
    public function __construct(public readonly int $x, public readonly int $y) {}
    public function tryMove(): string {
        try { $this->x = 100; return 'moved'; }
        catch (\Error $e) { return 'blocked'; }
    }
}
$p = new Point(3, 4);
echo "$p->x,$p->y\n";                 // 3,4
echo $p->tryMove(), "\n";             // blocked

// writing from outside the class is still blocked
try { $p->x = 50; } catch (\Error $e) { echo "external-blocked\n"; }

// the constructor's single initialization still works
class Lazy {
    public readonly string $name;
    public function __construct(string $n) { $this->name = $n; }
}
echo (new Lazy('ok'))->name, "\n";    // ok

// a readonly property initialized to a non-default value, then re-read
class Holder {
    public readonly array $data;
    public function __construct() { $this->data = [1, 2, 3]; }
}
echo implode(',', (new Holder)->data), "\n";
