<?php

// public private(set) - public read, private write
class Counter {
    public private(set) int $count = 0;
    public function inc(): void { $this->count++; }
}

$c = new Counter();
echo $c->count . "\n";
$c->inc();
echo $c->count . "\n";
try { $c->count = 99; echo "wrote\n"; } catch (Error $e) { echo "private(set): blocked\n"; }

// public protected(set) - public read, protected write
class Named {
    public protected(set) string $name = "anon";
}
class Renamable extends Named {
    public function rename(string $n): void { $this->name = $n; }
}
$r = new Renamable();
$r->rename("bob");
echo $r->name . "\n";
try { $r->name = "external"; echo "wrote\n"; } catch (Error $e) { echo "protected(set): blocked\n"; }

// shorthand: private(set) implies public read
class Ledger {
    private(set) int $balance = 100;
    public function deposit(int $n): void { $this->balance += $n; }
}
$l = new Ledger();
echo $l->balance . "\n";
$l->deposit(50);
echo $l->balance . "\n";
try { $l->balance = 0; } catch (Error $e) { echo "ledger blocked\n"; }

// constructor property promotion with asymmetric visibility
class Box {
    public function __construct(public private(set) int $size = 10) {}
    public function shrink(): void { $this->size--; }
}
$b = new Box(5);
echo $b->size . "\n";
$b->shrink();
echo $b->size . "\n";
try { $b->size = 0; echo "wrote\n"; } catch (Error $e) { echo "promoted: blocked\n"; }

// readonly + asymmetric (readonly is stricter)
class ReadOnlyAsymm {
    public private(set) readonly string $tag;
    public function __construct(string $t) { $this->tag = $t; }
}
$ro = new ReadOnlyAsymm("hello");
echo $ro->tag . "\n";
try { $ro->tag = "boom"; } catch (Error $e) { echo "ro+asymm: blocked\n"; }

// inherited asymmetric visibility
class Sub extends Counter {
    public function tryWrite(): string {
        try { $this->count = 5; return "wrote"; } catch (Error $e) { return "child blocked"; }
    }
}
echo (new Sub())->tryWrite() . "\n";
