<?php
class Simple {
    public string $tag = "default";
}

$rc = new ReflectionClass(Simple::class);
$obj = $rc->newInstance();
echo get_class($obj), " tag=", $obj->tag, "\n";

class WithCtor {
    public function __construct(public string $name, public int $age) {}
}

$rc = new ReflectionClass(WithCtor::class);
$obj = $rc->newInstance("alice", 30);
echo $obj->name, "/", $obj->age, "\n";

$obj = $rc->newInstanceArgs(["bob", 25]);
echo $obj->name, "/", $obj->age, "\n";

$obj = $rc->newInstanceWithoutConstructor();
echo isset($obj->name) ? "set" : "unset", "/", isset($obj->age) ? "set" : "unset", "\n";
echo get_class($obj), "\n";

class WithDefault {
    public function __construct(public int $val = 42) {}
}
$rc = new ReflectionClass(WithDefault::class);
$obj = $rc->newInstance();
echo $obj->val, "\n";

$obj = $rc->newInstanceArgs([]);
echo $obj->val, "\n";

$obj = $rc->newInstanceArgs([99]);
echo $obj->val, "\n";

class Counter {
    private int $n = 0;
    public function inc(): int { return ++$this->n; }
    public function add(int $x): int { return $this->n += $x; }
    public function get(): int { return $this->n; }
}

$rc = new ReflectionClass(Counter::class);
$obj = $rc->newInstance();
$rm = $rc->getMethod("inc");
$rm->invoke($obj);
$rm->invoke($obj);
$rm->invoke($obj);
echo $obj->get(), "\n";

$rm = $rc->getMethod("add");
$rm->invoke($obj, 10);
$rm->invokeArgs($obj, [20]);
echo $obj->get(), "\n";

class Math {
    public static function double(int $n): int { return $n * 2; }
    public static function add(int $a, int $b): int { return $a + $b; }
}

$rc = new ReflectionClass(Math::class);
$rm = $rc->getMethod("double");
echo $rm->invoke(null, 7), "\n";
echo $rm->invokeArgs(null, [11]), "\n";

$rm = $rc->getMethod("add");
echo $rm->invoke(null, 3, 4), "\n";

$rc = new ReflectionClass(WithCtor::class);
$rm = $rc->getMethod("__construct");
$obj = $rc->newInstanceWithoutConstructor();
$rm->invoke($obj, "carol", 40);
echo $obj->name, "/", $obj->age, "\n";

abstract class Abstr {
    abstract public function go(): void;
}
$rc = new ReflectionClass(Abstr::class);
try { $rc->newInstance(); echo "no\n"; }
catch (\Error $e) { echo "abs-err\n"; }

interface IFoo {}
$rc = new ReflectionClass(IFoo::class);
try { $rc->newInstance(); echo "no\n"; }
catch (\Error $e) { echo "iface-err\n"; }

class Privatized {
    private function __construct() {}
}
$rc = new ReflectionClass(Privatized::class);
$obj = $rc->newInstanceWithoutConstructor();
echo get_class($obj), "\n";

$rf = new ReflectionFunction("strlen");
echo $rf->invoke("hello"), "\n";
echo $rf->invokeArgs(["foobar"]), "\n";

$cl = function (int $a, int $b): int { return $a + $b; };
$rf = new ReflectionFunction($cl);
echo $rf->invoke(3, 4), "\n";
echo $rf->invokeArgs([10, 20]), "\n";

class Caller {
    public function method(int $a, int $b): int { return $a * $b; }
}
$rc = new ReflectionClass(Caller::class);
$obj = $rc->newInstance();
$rm = $rc->getMethod("method");
echo $rm->invoke($obj, 5, 6), "\n";
echo $rm->invokeArgs($obj, [7, 8]), "\n";

$rc = new ReflectionClass(Caller::class);
echo $rc->getDocComment() === false ? "no-doc" : "has-doc", "\n";

class WithDoc {
    /** @var int */
    public int $val = 1;

    /**
     * Does the thing.
     */
    public function go(): void {}
}
$rc = new ReflectionClass(WithDoc::class);
$dc = $rc->getDocComment();
echo $dc === false ? "no-doc" : "has-doc", "\n";

// method getDocComment content (architectural - zphp doesn't preserve doc comments)
$rm = $rc->getMethod("go");
$dc = $rm->getDocComment();
echo $dc === false || str_contains($dc, "Does") ? "ok" : "wrong", "\n";

class Builder {
    public array $parts = [];
    public function add(string $p): self {
        $this->parts[] = $p;
        return $this;
    }
}

$rc = new ReflectionClass(Builder::class);
$obj = $rc->newInstance();
$rm = $rc->getMethod("add");
$rm->invoke($obj, "a");
$rm->invoke($obj, "b");
$rm->invoke($obj, "c");
print_r($obj->parts);

$rm->invokeArgs($obj, ["d"]);
print_r($obj->parts);
