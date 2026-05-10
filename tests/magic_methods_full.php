<?php
class M {
    private array $data = [];

    public function __get(string $name): mixed {
        return $this->data[$name] ?? "missing-$name";
    }

    public function __set(string $name, mixed $value): void {
        $this->data[$name] = $value;
    }

    public function __isset(string $name): bool {
        return isset($this->data[$name]);
    }

    public function __unset(string $name): void {
        unset($this->data[$name]);
    }
}

$m = new M;
echo $m->x, "\n"; // missing-x
$m->y = 42;
echo $m->y, "\n"; // 42
echo isset($m->y) ? "y-set" : "no", "\n";
echo isset($m->never) ? "ns" : "ns-missing", "\n";
unset($m->y);
echo isset($m->y) ? "still" : "unset-ok", "\n";

class Recorder {
    public array $log = [];
    public function __call(string $name, array $args): string {
        $this->log[] = "$name(" . implode(",", $args) . ")";
        return "called-$name";
    }
    public static function __callStatic(string $name, array $args): string {
        return "static-$name(" . implode(",", $args) . ")";
    }
}

$r = new Recorder;
echo $r->doStuff(1, 2, 3), "\n";
echo $r->other("a", "b"), "\n";
print_r($r->log);

echo Recorder::ping("x", "y"), "\n";

class Stringy {
    public function __construct(public string $msg) {}
    public function __toString(): string {
        return "Stringy[" . $this->msg . "]";
    }
}

$s = new Stringy("hello");
echo $s, "\n";
echo "concat: " . $s, "\n";
echo "interp: $s\n";
echo "{$s}.txt\n";

// __toString in coercion
$out = (string)$s;
echo $out, "\n";

// passing object where string expected
function takeStr(string $s): int { return strlen($s); }
echo takeStr($s), "\n";

class Caller {
    public int $val = 100;
    public function __invoke(int $x): int {
        return $this->val + $x;
    }
}

$c = new Caller;
echo $c(5), "\n";

// is_callable on invokable
var_dump(is_callable($c));

// invoke via array_map
$results = array_map($c, [1, 2, 3]);
print_r($results);

class WithBoth {
    public string $public_prop = "public-val";
    private array $private_data = [];

    public function __get(string $name): string {
        return "magic-get-$name";
    }
}

$w = new WithBoth;
echo $w->public_prop, "\n"; // public-val (no magic)
echo $w->missing, "\n";     // magic-get-missing

class NoMagic {
    public string $real = "x";
}
$n = new NoMagic;
echo isset($n->real) ? "y" : "n", "\n";
echo isset($n->fake) ? "y" : "n", "\n";

// __get returns null - PHP allows
class NullGet {
    public function __get(string $name): mixed {
        return null;
    }
}
$ng = new NullGet;
var_dump($ng->anything);
echo isset($ng->anything) ? "y" : "n", "\n"; // n (null isn't set)

// __isset overrides isset
class IsSetMagic {
    public function __isset(string $name): bool {
        return $name === "x";
    }
    public function __get(string $name): string {
        return "g-$name";
    }
}
$i = new IsSetMagic;
echo isset($i->x) ? "y" : "n", "\n"; // y
echo isset($i->y) ? "y" : "n", "\n"; // n
echo $i->y, "\n"; // g-y (still calls __get)

// concatenation triggers __toString
class Labeled {
    public function __construct(public string $label) {}
    public function __toString(): string {
        return "[" . $this->label . "]";
    }
}

$l = new Labeled("foo");
echo "before-" . $l . "-after\n";
echo $l . "\n";

// in array_map
$objs = [new Labeled("a"), new Labeled("b")];
$strs = array_map(fn($o) => (string)$o, $objs);
print_r($strs);

// implode joins __toString
echo implode(",", $objs), "\n";

// printf with %s
printf("name=%s\n", $l);

// instance of __invoke is callable
$inv = new Caller;
echo array_sum(array_map($inv, [10, 20])), "\n";

// __callStatic via FQN
echo Recorder::someStatic("a", "b", "c"), "\n";

// magic on inherited class
class Base {
    public function __get(string $n): string { return "base-$n"; }
}
class Sub extends Base {}
$s = new Sub;
echo $s->foo, "\n"; // base-foo

// override __get in subclass
class Sub2 extends Base {
    public function __get(string $n): string { return "sub-$n"; }
}
$s2 = new Sub2;
echo $s2->foo, "\n"; // sub-foo
