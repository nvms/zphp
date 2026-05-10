<?php
class C {
    public int $pub = 1;
    protected int $prot = 2;
    private int $priv = 3;
    public static int $static_pub = 100;
    private static int $static_priv = 200;
}

$reader = function () {
    return [$this->pub, $this->prot, $this->priv];
};

$bound = Closure::bind($reader, new C, C::class);
print_r($bound());

$bound2 = Closure::bind($reader, new C, "C");
print_r($bound2());

$static_reader = function () {
    return [self::$static_pub, self::$static_priv];
};
$bound = Closure::bind($static_reader, null, C::class);
print_r($bound());

$instance_static = function () {
    return [static::$static_pub, $this->pub];
};
$bound = Closure::bind($instance_static, new C, C::class);
print_r($bound());

class Animal {
    public string $species = "generic";
    public static function make(): static {
        return new static;
    }
    public function name(): string {
        $f = function () {
            return static::class;
        };
        return $f->call($this);
    }
}
class Dog extends Animal {
    public string $species = "dog";
}

echo (new Animal)->name(), "\n";
echo (new Dog)->name(), "\n";

$cl = function () {
    return static::$static_pub;
};
echo $cl->call(new C), "\n";

class Counter {
    private int $n = 0;
    public function getInc(): callable {
        return function () { return ++$this->n; };
    }
}
$c = new Counter;
$inc = $c->getInc();
echo $inc(), " ", $inc(), " ", $inc(), "\n";

class Box {
    private int $val = 5;
}

$cl = function () { return $this->val * 2; };
$b = new Box;
echo $cl->call($b), "\n";

class Parent_ {
    public function get(): int { return 1; }
    public function makeArrow() { return fn() => $this->get(); }
}
class Child_ extends Parent_ {
    public function get(): int { return 99; }
}
echo (new Child_)->makeArrow()(), "\n";

class WithProtected {
    protected string $tag = "tag-val";
}

class Ext extends WithProtected {
    public function read(): string {
        $f = function () { return $this->tag; };
        return $f();
    }
}
echo (new Ext)->read(), "\n";

class Container {
    private array $items = [];
    public function adder(): callable {
        return function (string $key, mixed $value): void {
            $this->items[$key] = $value;
        };
    }
    public function dump(): array { return $this->items; }
}

$c = new Container;
$add = $c->adder();
$add("a", 1);
$add("b", 2);
$add("c", 3);
print_r($c->dump());

class HasInvoke {
    private int $val;
    public function __construct(int $v) { $this->val = $v; }
    public function __invoke(int $n): int { return $this->val * $n; }
}

$inv = new HasInvoke(7);
echo $inv(3), "\n";

class DoubleInvoke {
    public int $multiplier = 5;
    public function __invoke(int $x): int { return $x * $this->multiplier; }
}
$inv = new DoubleInvoke;
echo array_sum(array_map($inv, [1, 2, 3])), "\n";

class Methods {
    private int $x = 10;
    public static int $static_x = 100;

    public function makeReader(): callable {
        return fn() => [$this->x, self::$static_x];
    }
}

$m = new Methods;
$reader = $m->makeReader();
print_r($reader());

class Settings {
    public static array $cfg = ["key" => "val"];
}

$cl = function () { return Settings::$cfg["key"]; };
echo $cl(), "\n";

$bound = Closure::bind($cl, null, Settings::class);
echo $bound(), "\n";

$cl = function () { return self::$cfg["key"]; };
$bound = Closure::bind($cl, null, Settings::class);
echo $bound(), "\n";

class GreetA {
    public string $tag = "A";
    public function greet(): string {
        return "from-" . $this->tag;
    }
}
class GreetB extends GreetA {
    public string $tag = "B";
}

$cl = function () { return $this->greet(); };
echo $cl->call(new GreetA), "\n";
echo $cl->call(new GreetB), "\n";

class StaticAccess {
    public static int $shared = 0;
    public static function inc(): int {
        return ++static::$shared;
    }
}

$cl = function () { return static::inc(); };
echo $cl->call(new StaticAccess), "\n";
echo $cl->call(new StaticAccess), "\n";
echo StaticAccess::$shared, "\n";

class PartialAccess {
    private string $secret = "private!";
}

$leak = function () { return $this->secret; };
echo $leak->call(new PartialAccess), "\n";

class WithCtor {
    public function __construct(public int $x) {}
    public function getter() { return fn() => $this->x; }
}
$wc = new WithCtor(42);
echo $wc->getter()(), "\n";

class Dual {
    public function makeA(): callable { return fn() => "A:" . $this->id(); }
    public function makeB(): callable { return function () { return "B:" . $this->id(); }; }
    public function id(): int { return 1; }
}
$d = new Dual;
echo $d->makeA()(), " ", $d->makeB()(), "\n";
