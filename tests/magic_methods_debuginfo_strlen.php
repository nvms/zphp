<?php
class Box {
    private array $data = [];
    public function __get($name) { echo "get($name) "; return $this->data[$name] ?? null; }
    public function __set($name, $val) { echo "set($name=$val) "; $this->data[$name] = $val; }
    public function __isset($name) { echo "isset($name) "; return isset($this->data[$name]); }
    public function __unset($name) { echo "unset($name) "; unset($this->data[$name]); }
}

$b = new Box;
$b->foo = "bar";
echo $b->foo, "\n";
echo isset($b->foo) ? "y" : "n", "\n";
unset($b->foo);
echo isset($b->foo) ? "y" : "n", "\n";

class Caller {
    public function __call($name, $args) { return "$name(" . implode(",", $args) . ")"; }
    public static function __callStatic($name, $args) { return "static:$name(" . implode(",", $args) . ")"; }
}

$c = new Caller;
echo $c->hello("a", "b"), "\n";
echo Caller::world("x", "y"), "\n";

class Stringy {
    public function __toString(): string { return "stringified"; }
}
echo new Stringy, "\n";
echo "value: " . new Stringy, "\n";

class Inv {
    public function __invoke(int $x): int { return $x * 2; }
}
$i = new Inv;
echo $i(5), "\n";
echo is_callable($i) ? "y" : "n", "\n";

class Dbg {
    public int $public_x = 1;
    private int $private_y = 2;
    public function __debugInfo(): array { return ["custom" => "info", "x" => $this->public_x]; }
}
print_r(new Dbg);

class Cloneable {
    public array $items = [];
    public function __clone() { $this->items[] = "cloned"; }
}
$c1 = new Cloneable;
$c1->items[] = "a";
$c2 = clone $c1;
print_r($c1->items);
print_r($c2->items);

class Sleepy {
    public int $a = 1;
    public int $b = 2;
    public int $c = 3;
    public function __sleep(): array { return ["a", "c"]; }
    public function __wakeup(): void { $this->b = 999; }
}
$s = new Sleepy;
$un = unserialize(serialize($s));
echo $un->a, " ", $un->b, " ", $un->c, "\n";

class WithMagic74 {
    public string $name = "alice";
    public int $age = 30;
    public function __serialize(): array { return ["n" => $this->name, "a" => $this->age]; }
    public function __unserialize(array $data): void {
        $this->name = strtoupper($data["n"]);
        $this->age = $data["a"] + 100;
    }
}
$w = new WithMagic74;
$un = unserialize(serialize($w));
echo $un->name, " ", $un->age, "\n";

class StrictCall {
    public function existing(): string { return "real"; }
    public function __call($n, $args): string { return "magic($n)"; }
}
$sc = new StrictCall;
echo $sc->existing(), "\n";
echo $sc->missing(), "\n";

class MagicStatic {
    public static function existing(): string { return "real static"; }
    public static function __callStatic($n, $args): string { return "static magic($n)"; }
}
echo MagicStatic::existing(), "\n";
echo MagicStatic::missing(), "\n";

class Convertable {
    public function __toString(): string { return "converted"; }
}
$cv = new Convertable;
echo (string)$cv, "\n";
echo strlen($cv), "\n";

class InvokeWithCapture {
    public int $base;
    public function __construct(int $b) { $this->base = $b; }
    public function __invoke(int $x): int { return $this->base + $x; }
}
$iwc = new InvokeWithCapture(100);
echo $iwc(50), "\n";
echo array_map(new InvokeWithCapture(10), [1, 2, 3])[2], "\n";
