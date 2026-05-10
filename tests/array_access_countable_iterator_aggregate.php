<?php
class Container implements ArrayAccess, Countable {
    private array $data;
    public function __construct(array $data = []) { $this->data = $data; }
    public function offsetExists(mixed $k): bool { return isset($this->data[$k]); }
    public function offsetGet(mixed $k): mixed { return $this->data[$k] ?? null; }
    public function offsetSet(mixed $k, mixed $v): void {
        if ($k === null) $this->data[] = $v;
        else $this->data[$k] = $v;
    }
    public function offsetUnset(mixed $k): void { unset($this->data[$k]); }
    public function count(): int { return count($this->data); }
    public function dump(): array { return $this->data; }
}

$c = new Container;
$c["a"] = 1;
$c["b"] = 2;
$c[] = 99;
echo count($c), "\n";
echo $c["a"], "\n";
echo $c["b"], "\n";
echo $c[0], "\n";
echo isset($c["a"]) ? "y" : "n", "\n";
echo isset($c["z"]) ? "y" : "n", "\n";
unset($c["a"]);
echo isset($c["a"]) ? "y" : "n", "\n";
echo count($c), "\n";
print_r($c->dump());

$c = new Container(["x"=>10, "y"=>20]);
echo count($c), "\n";
echo $c["x"], " ", $c["y"], "\n";

class TypedList implements ArrayAccess, Countable {
    private array $items = [];
    public function offsetExists(mixed $k): bool { return is_int($k) && $k >= 0 && $k < count($this->items); }
    public function offsetGet(mixed $k): mixed { return $this->items[$k] ?? null; }
    public function offsetSet(mixed $k, mixed $v): void {
        if (!is_string($v)) throw new \TypeError("expected string");
        if ($k === null) $this->items[] = $v;
        else $this->items[$k] = $v;
    }
    public function offsetUnset(mixed $k): void { unset($this->items[$k]); }
    public function count(): int { return count($this->items); }
}

$l = new TypedList;
$l[] = "a";
$l[] = "b";
$l[] = "c";
echo count($l), "\n";
echo $l[0], $l[1], $l[2], "\n";
try { $l[] = 42; } catch (\TypeError $e) { echo "te\n"; }

class TagList implements IteratorAggregate, Countable {
    public function __construct(private array $tags = []) {}
    public function getIterator(): ArrayIterator { return new ArrayIterator($this->tags); }
    public function count(): int { return count($this->tags); }
}

$t = new TagList(["red", "blue", "green"]);
foreach ($t as $k => $v) echo $k, "=", $v, "\n";
echo count($t), "\n";
echo iterator_count($t), "\n";

$arr = iterator_to_array($t);
print_r($arr);

class Pairs implements IteratorAggregate {
    public function __construct(private array $pairs = []) {}
    public function getIterator(): Iterator {
        return new ArrayIterator($this->pairs);
    }
}

$p = new Pairs(["a" => 1, "b" => 2, "c" => 3]);
foreach ($p as $k => $v) echo "$k=$v ";
echo "\n";

class Composite implements ArrayAccess, IteratorAggregate, Countable {
    public array $data = [];
    public function offsetExists(mixed $k): bool { return isset($this->data[$k]); }
    public function offsetGet(mixed $k): mixed { return $this->data[$k]; }
    public function offsetSet(mixed $k, mixed $v): void {
        if ($k === null) $this->data[] = $v;
        else $this->data[$k] = $v;
    }
    public function offsetUnset(mixed $k): void { unset($this->data[$k]); }
    public function getIterator(): Iterator { return new ArrayIterator($this->data); }
    public function count(): int { return count($this->data); }
}

$c = new Composite;
$c["x"] = 1;
$c["y"] = 2;
$c[] = 99;
echo count($c), "\n";
foreach ($c as $k => $v) echo "$k=$v ";
echo "\n";

class Generators implements IteratorAggregate {
    public function getIterator(): Generator {
        yield "a" => 1;
        yield "b" => 2;
        yield "c" => 3;
    }
}
$g = new Generators;
foreach ($g as $k => $v) echo "$k=>$v ";
echo "\n";

echo (new TagList(["x"])) instanceof IteratorAggregate ? "y" : "n", "\n";
echo (new TagList(["x"])) instanceof Traversable ? "y" : "n", "\n";
echo (new TagList(["x"])) instanceof Iterator ? "y" : "n", "\n";

class WithDefault implements ArrayAccess {
    private array $data = ["k" => "v"];
    public function offsetExists(mixed $k): bool { return isset($this->data[$k]); }
    public function offsetGet(mixed $k): mixed {
        return $this->data[$k] ?? "default";
    }
    public function offsetSet(mixed $k, mixed $v): void { $this->data[$k] = $v; }
    public function offsetUnset(mixed $k): void { unset($this->data[$k]); }
}
$w = new WithDefault;
echo $w["k"], "\n";
echo $w["missing"], "\n";

class StringSetter implements ArrayAccess {
    private array $store = [];
    public function offsetExists(mixed $k): bool { return isset($this->store[$k]); }
    public function offsetGet(mixed $k): mixed { return $this->store[$k] ?? null; }
    public function offsetSet(mixed $k, mixed $v): void {
        $this->store[$k] = (string)$v;
    }
    public function offsetUnset(mixed $k): void { unset($this->store[$k]); }
}
$s = new StringSetter;
$s["a"] = 42;
$s["b"] = true;
$s["c"] = 3.14;
echo $s["a"], "|", $s["b"], "|", $s["c"], "\n";

class CallChain implements ArrayAccess, Countable {
    private array $d = [];
    public function offsetExists(mixed $k): bool { return isset($this->d[$k]); }
    public function offsetGet(mixed $k): mixed { return $this->d[$k] ?? null; }
    public function offsetSet(mixed $k, mixed $v): void {
        if ($k === null) $this->d[] = $v;
        else $this->d[$k] = $v;
    }
    public function offsetUnset(mixed $k): void { unset($this->d[$k]); }
    public function count(): int { return count($this->d); }
}
$c = new CallChain;
for ($i = 0; $i < 5; $i++) $c[] = $i * 10;
echo count($c), "\n";
$sum = 0;
for ($i = 0; $i < count($c); $i++) $sum += $c[$i];
echo $sum, "\n";
