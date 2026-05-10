<?php
trait Greet {
    public function hello(): string { return "hi"; }
}

class A { use Greet; }
echo (new A)->hello(), "\n";

trait HasName {
    abstract public function getName(): string;
    public function greet(): string {
        return "hello, " . $this->getName();
    }
}

class B {
    use HasName;
    public function getName(): string { return "Bob"; }
}
echo (new B)->greet(), "\n";

trait Counter {
    private int $count = 0;
    abstract public function step(): int;
    public function tick(): int {
        $this->count += $this->step();
        return $this->count;
    }
}

class C1 {
    use Counter;
    public function step(): int { return 1; }
}
class C5 {
    use Counter;
    public function step(): int { return 5; }
}
$c = new C1;
echo $c->tick(), " ", $c->tick(), " ", $c->tick(), "\n";
$c = new C5;
echo $c->tick(), " ", $c->tick(), "\n";

trait T1 { public function hello() { return "T1"; } public function shared() { return "T1::shared"; } }
trait T2 { public function hello() { return "T2"; } public function shared() { return "T2::shared"; } }

class Resolved {
    use T1, T2 {
        T1::hello insteadof T2;
        T2::hello as helloT2;
        T2::shared insteadof T1;
        T1::shared as sharedT1;
    }
}

$r = new Resolved;
echo $r->hello(), "\n";
echo $r->helloT2(), "\n";
echo $r->shared(), "\n";
echo $r->sharedT1(), "\n";

trait Hidden {
    public function pub() { return "pub"; }
    public function rename() { return "renamed"; }
}

class WithRename {
    use Hidden { rename as protected aliasedRename; }
    public function callIt() { return $this->aliasedRename(); }
}

echo (new WithRename)->callIt(), "\n";

trait Constants {
    public const VERSION = "1.0";
    public const MAX = 100;
}

class WithConsts {
    use Constants;
}

echo WithConsts::VERSION, "\n";
echo WithConsts::MAX, "\n";

trait Props {
    public string $tag = "trait-tag";
    public int $count = 0;
}

class P {
    use Props;
}

$p = new P;
echo $p->tag, "\n";
echo $p->count, "\n";
$p->count++;
echo $p->count, "\n";

trait Multi1 { public string $shared = "from-1"; }
trait Multi2 { public int $other = 42; }

class M {
    use Multi1, Multi2;
}

$m = new M;
echo $m->shared, "\n";
echo $m->other, "\n";

trait Stat {
    public static int $counter = 0;
    public static function inc(): int { return ++self::$counter; }
}

class S {
    use Stat;
}

echo S::inc(), " ", S::inc(), " ", S::inc(), "\n";
echo S::$counter, "\n";

trait Util {
    public function double(int $x): int { return $x * 2; }
}

class WithUtil {
    use Util;
    public function callDouble(int $x): int { return $this->double($x); }
}

echo (new WithUtil)->callDouble(7), "\n";

trait Logger {
    public function log(string $msg): string { return "[" . static::class . "] " . $msg; }
}

class App {
    use Logger;
}
class Service extends App {}

echo (new App)->log("hello"), "\n";
echo (new Service)->log("hi"), "\n";

trait Ts {
    public function method(): string { return self::class . "::method"; }
}

class Inh1 { use Ts; }
class Inh2 extends Inh1 {}

echo (new Inh1)->method(), "\n";
echo (new Inh2)->method(), "\n";

trait Diamond1 { public function f() { return "D1"; } }
trait Diamond2 { public function f() { return "D2"; } }
trait Combo {
    use Diamond1, Diamond2 { Diamond1::f insteadof Diamond2; }
}

class Use1 {
    use Combo;
}
echo (new Use1)->f(), "\n";

trait Abs {
    abstract public function name(): string;
}

class WithAbs {
    use Abs;
    public function name(): string { return "concrete"; }
}
echo (new WithAbs)->name(), "\n";
