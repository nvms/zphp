<?php
class Bag implements ArrayAccess, Countable {
    private array $data = [];
    public function offsetExists(mixed $offset): bool {
        return array_key_exists($offset, $this->data);
    }
    public function offsetGet(mixed $offset): mixed {
        return $this->data[$offset] ?? null;
    }
    public function offsetSet(mixed $offset, mixed $value): void {
        if ($offset === null) $this->data[] = $value;
        else $this->data[$offset] = $value;
    }
    public function offsetUnset(mixed $offset): void {
        unset($this->data[$offset]);
    }
    public function count(): int {
        return count($this->data);
    }
    public function dump(): array {
        return $this->data;
    }
}

$b = new Bag;
$b["a"] = 1;
$b["b"] = 2;
$b[] = "appended"; // null offset = append
echo count($b), "\n"; // 3
echo $b["a"], " ", $b["b"], "\n";
print_r($b->dump());

// isset triggers offsetExists
var_dump(isset($b["a"]));
var_dump(isset($b["nope"]));

// unset triggers offsetUnset
unset($b["a"]);
echo count($b), "\n";
var_dump(isset($b["a"]));

// offsetGet on missing returns null
var_dump($b["missing"]);

// foreach doesn't iterate ArrayAccess by default (only Iterator/IteratorAggregate)
$count = 0;
foreach ($b as $k => $v) $count++;
echo "iter:", $count, "\n"; // 0

class Iterable_ extends Bag implements IteratorAggregate {
    public function getIterator(): Iterator {
        return new ArrayIterator($this->dump());
    }
}
$i = new Iterable_;
$i["x"] = 10;
$i["y"] = 20;
foreach ($i as $k => $v) echo "$k=$v ";
echo "\n";

// custom collection example
class Collection implements ArrayAccess, Countable, IteratorAggregate {
    private array $items = [];

    public function offsetExists(mixed $offset): bool {
        return isset($this->items[$offset]);
    }
    public function offsetGet(mixed $offset): mixed {
        return $this->items[$offset] ?? throw new \OutOfBoundsException("$offset");
    }
    public function offsetSet(mixed $offset, mixed $value): void {
        if ($offset === null) {
            $this->items[] = $value;
        } else {
            $this->items[$offset] = $value;
        }
    }
    public function offsetUnset(mixed $offset): void {
        unset($this->items[$offset]);
    }
    public function count(): int {
        return count($this->items);
    }
    public function getIterator(): Iterator {
        return new ArrayIterator($this->items);
    }
}

$c = new Collection;
$c[] = "a";
$c[] = "b";
$c[] = "c";
echo count($c), "\n";
foreach ($c as $k => $v) echo "$k=$v ";
echo "\n";

// access by int key
echo $c[0], " ", $c[1], "\n";

// missing throws
try { $x = $c[99]; echo "no\n"; } catch (\OutOfBoundsException $e) { echo "oob:", $e->getMessage(), "\n"; }

// isset returns false for missing
var_dump(isset($c[99]));

// nested arrays via ArrayAccess won't auto-vivify (PHP behavior)
$obj = new Collection;
$obj["inner"] = [];
// indirect modification of overloaded element notice (architectural)

// isset on nested
var_dump(isset($obj["inner"]));

// count() builtin uses Countable
class MyCount implements Countable {
    public function count(): int {
        return 42;
    }
}
echo count(new MyCount), "\n"; // 42

// ArrayObject - built-in ArrayAccess+IteratorAggregate
$ao = new ArrayObject(["a" => 1, "b" => 2, "c" => 3]);
echo count($ao), "\n";
echo $ao["a"], "\n";
$ao["new"] = "val";
echo isset($ao["new"]) ? "y" : "n", "\n";

foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";

unset($ao["a"]);
echo count($ao), "\n";

// ArrayObject ARRAY_AS_PROPS
$ao2 = new ArrayObject(["x" => 10, "y" => 20], ArrayObject::ARRAY_AS_PROPS);
echo $ao2->x, "/", $ao2->y, "\n";
$ao2->z = 30;
echo $ao2["z"], "\n";

// readonly via offsetSet that throws
class ReadOnlyArr implements ArrayAccess {
    public function __construct(private array $data) {}
    public function offsetExists(mixed $o): bool { return isset($this->data[$o]); }
    public function offsetGet(mixed $o): mixed { return $this->data[$o] ?? null; }
    public function offsetSet(mixed $o, mixed $v): void { throw new \LogicException("read-only"); }
    public function offsetUnset(mixed $o): void { throw new \LogicException("read-only"); }
}

$r = new ReadOnlyArr(["a" => 1]);
echo $r["a"], "\n";
try { $r["b"] = 2; echo "no\n"; }
catch (\LogicException $e) { echo "ro\n"; }

// nested coalesce on ArrayAccess
class NullableBag implements ArrayAccess {
    private array $d = ["found" => "yes"];
    public function offsetExists(mixed $o): bool { return isset($this->d[$o]); }
    public function offsetGet(mixed $o): mixed { return $this->d[$o] ?? null; }
    public function offsetSet(mixed $o, mixed $v): void { $this->d[$o] = $v; }
    public function offsetUnset(mixed $o): void { unset($this->d[$o]); }
}

$n = new NullableBag;
echo $n["found"] ?? "default", "\n"; // yes
echo $n["missing"] ?? "default", "\n"; // default

// double-call detection
class Counter implements ArrayAccess {
    public int $exists_calls = 0;
    public int $get_calls = 0;
    private array $d = ["k" => "v"];
    public function offsetExists(mixed $o): bool { $this->exists_calls++; return isset($this->d[$o]); }
    public function offsetGet(mixed $o): mixed { $this->get_calls++; return $this->d[$o] ?? null; }
    public function offsetSet(mixed $o, mixed $v): void { $this->d[$o] = $v; }
    public function offsetUnset(mixed $o): void { unset($this->d[$o]); }
}

$c = new Counter;
$x = $c["k"];
echo "after-get exists=$c->exists_calls get=$c->get_calls\n";
$x = isset($c["k"]);
echo "after-isset exists=$c->exists_calls get=$c->get_calls\n";
echo "after-coalesce exists=$c->exists_calls get=$c->get_calls\n";
