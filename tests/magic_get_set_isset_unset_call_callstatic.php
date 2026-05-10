<?php
class Bag {
    private array $data = [];

    public function __get(string $name): mixed {
        echo "[get:$name] ";
        return $this->data[$name] ?? null;
    }

    public function __set(string $name, mixed $value): void {
        echo "[set:$name=$value] ";
        $this->data[$name] = $value;
    }

    public function __isset(string $name): bool {
        echo "[isset:$name] ";
        return isset($this->data[$name]);
    }

    public function __unset(string $name): void {
        echo "[unset:$name] ";
        unset($this->data[$name]);
    }
}

$b = new Bag;
$b->x = 5;
$b->y = 10;
echo "\n";
echo $b->x, "\n";
echo $b->y, "\n";

echo isset($b->x) ? "y" : "n", "\n";
echo isset($b->z) ? "y" : "n", "\n";
echo isset($b->x), "\n";

unset($b->x);
echo isset($b->x) ? "y" : "n", "\n";

class CaseInsensitiveBag {
    private array $store = [];
    public function __get(string $name): mixed {
        return $this->store[strtolower($name)] ?? null;
    }
    public function __set(string $name, mixed $value): void {
        $this->store[strtolower($name)] = $value;
    }
    public function __isset(string $name): bool { return isset($this->store[strtolower($name)]); }
}
$c = new CaseInsensitiveBag;
$c->FOO = 1;
echo $c->foo, " ", $c->Foo, " ", $c->FOO, "\n";

class WithCall {
    public function __call(string $name, array $args): string {
        return "called:$name(" . implode(",", $args) . ")";
    }
}
$w = new WithCall;
echo $w->hello(), "\n";
echo $w->add(1, 2, 3), "\n";
echo $w->greet("alice"), "\n";

class WithStatic {
    public static function __callStatic(string $name, array $args): string {
        return "static:$name(" . implode(",", $args) . ")";
    }
}
echo WithStatic::ping(), "\n";
echo WithStatic::echo("hi"), "\n";

class Both {
    public function __call(string $n, array $a): string {
        return "instance:$n";
    }
    public static function __callStatic(string $n, array $a): string {
        return "static:$n";
    }
}
echo (new Both)->foo(), "\n";
echo Both::bar(), "\n";

class WithMethodsAndCall {
    public function known(): string { return "real-known"; }
    public function __call(string $n, array $a): string {
        return "fallback:$n";
    }
}
$o = new WithMethodsAndCall;
echo $o->known(), "\n";
echo $o->unknown(), "\n";

class ProtectedAccess {
    protected int $secret = 99;
    public function __get(string $n): mixed {
        return "trap:$n";
    }
}
$p = new ProtectedAccess;
echo $p->secret, "\n";
echo $p->public_one, "\n";

class PrivateAccess {
    private int $hidden = 1;
    public function __get(string $n): mixed { return "g:$n"; }
    public function __set(string $n, mixed $v): void { echo "s:$n=$v\n"; }
    public function __isset(string $n): bool { return true; }
    public function __unset(string $n): void { echo "u:$n\n"; }
    public function reveal(): int { return $this->hidden; }
}
$p = new PrivateAccess;
echo $p->hidden, "\n";
$p->hidden = 100;
echo $p->reveal(), "\n";
echo isset($p->hidden) ? "y" : "n", "\n";
echo isset($p->anything) ? "y" : "n", "\n";
unset($p->anything);

class Recursive {
    public function __get(string $n): mixed {
        if ($n === "self") return $this;
        return null;
    }
}
$r = new Recursive;
echo $r->self === $r ? "y" : "n", "\n";

class Counter {
    private int $count = 0;
    public function __get(string $n): int { return ++$this->count; }
}
$c = new Counter;
echo $c->x, " ", $c->y, " ", $c->z, "\n";

class WithChain {
    private array $vals = [];
    public function __set(string $n, mixed $v): void { $this->vals[$n] = $v; }
    public function __get(string $n): mixed { return $this->vals[$n] ?? null; }
}
$w = new WithChain;
$w->a = 1;
$w->b = 2;
echo $w->a + $w->b, "\n";

class ReturnsObj {
    public function __get(string $n): object {
        return new class { public int $x = 42; };
    }
}
echo (new ReturnsObj)->any->x, "\n";

class FluentCall {
    public function __call(string $n, array $a): self {
        echo "call:$n ";
        return $this;
    }
}
$f = (new FluentCall)->a()->b()->c();
echo "\n";

class WithProperty {
    public int $defined = 7;
    public function __get(string $n): mixed {
        return "magic:$n";
    }
}
$w = new WithProperty;
echo $w->defined, "\n";
echo $w->undefined, "\n";

class WithCallAndNum {
    public function __call(string $n, array $a): int { return count($a); }
}
$w = new WithCallAndNum;
echo $w->any(1, 2, 3, 4), "\n";

class StaticBoth {
    public static function __callStatic(string $n, array $a): string {
        return "scs:$n:" . count($a);
    }
}
echo StaticBoth::go(), "\n";
echo StaticBoth::run("a", "b"), "\n";
