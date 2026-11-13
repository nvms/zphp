<?php

class Test {
    public function __construct(
        public $prop {
            get { echo "get\n"; return 1; }
            set { echo "set($value)\n"; }
        },
    ) {}
}

$test = new Test(42);
echo $test->prop, "\n";

class WithDefault {
    public function __construct(
        public $prop = 42 {
            get => print("Getting\n");
            set { print("Setting\n"); }
        }
    ) {
        echo "Constructor\n";
    }
}

echo "Pre-test\n";
$t = new WithDefault;
$t->prop;
$t->prop = 42;
$r = new ReflectionProperty(WithDefault::class, 'prop');
var_dump($r->hasDefaultValue(), $r->isPromoted(), $r->hasHooks());

class Doubler {
    public function __construct(
        $prop { set => $value * 2; }
    ) {}
}
var_dump(new Doubler(42));
var_dump((new ReflectionClass(Doubler::class))->newInstanceWithoutConstructor());

class Typed {
    public function __construct(
        public private(set) int $count = 0 {
            set(int $value) {
                echo "count set to $value\n";
                $this->count = $value;
            }
        },
        public string $name = 'x',
    ) {}

    public function bump() { $this->count++; }
}
$typed = new Typed(3, 'n');
$typed->bump();
var_dump($typed);
try {
    $typed->count = 9;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump(array_map(fn($p) => $p->getName(), (new ReflectionClass(Typed::class))->getProperties()));
