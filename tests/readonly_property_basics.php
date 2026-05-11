<?php
class P {
    public readonly string $name;
    public readonly int $age;
    public function __construct(string $n, int $a) {
        $this->name = $n;
        $this->age = $a;
    }
}

$p = new P("alice", 30);
echo $p->name, " ", $p->age, "\n";
try { $p->name = "bob"; } catch (Error $e) { echo "ro1\n"; }
try { $p->age = 99; } catch (Error $e) { echo "ro2\n"; }
echo $p->name, " ", $p->age, "\n";

class Q {
    public function __construct(
        public readonly string $tag,
        public readonly array $items = [],
    ) {}
}

$q = new Q("x", [1,2,3]);
echo $q->tag, "\n";
print_r($q->items);
try { $q->tag = "y"; } catch (Error $e) { echo "ro\n"; }

class R {
    public function __construct(public readonly string $val = "default") {}
}

echo (new R)->val, "\n";
echo (new R("custom"))->val, "\n";

readonly class Point {
    public function __construct(public float $x, public float $y) {}
}

$pt = new Point(1.5, 2.5);
echo $pt->x, " ", $pt->y, "\n";
try { $pt->x = 100; } catch (Error $e) { echo "ro class\n"; }

class WithMutable {
    public string $mutable = "default";
    public readonly string $immutable;
    public function __construct(string $im) { $this->immutable = $im; }
}

$wm = new WithMutable("set");
$wm->mutable = "changed";
echo $wm->mutable, "\n";
try { $wm->immutable = "new"; } catch (Error $e) { echo "ro\n"; }
echo $wm->immutable, "\n";

class Settings {
    public function __construct(
        public readonly string $env = "prod",
        public readonly int $port = 8080,
    ) {}
    public function withEnv(string $env): static {
        return new static($env, $this->port);
    }
}

$s = new Settings;
echo $s->env, " ", $s->port, "\n";
$s2 = $s->withEnv("dev");
echo $s2->env, " ", $s2->port, "\n";

class Pair {
    public function __construct(public readonly int $a, public readonly int $b) {}
}

$pa = new Pair(1, 2);
$pa2 = clone $pa;
echo $pa->a, " ", $pa2->a, "\n";

class Reflectable {
    public function __construct(public readonly string $tag = "t") {}
}
$rp = new ReflectionProperty(Reflectable::class, "tag");
echo $rp->isReadOnly() ? "y" : "n", "\n";
