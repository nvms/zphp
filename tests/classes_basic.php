<?php

// basic class with constructor and methods
class Animal {
    public $name;
    public $sound;

    public function __construct($name, $sound) {
        $this->name = $name;
        $this->sound = $sound;
    }

    public function speak() {
        return $this->name . ' says ' . $this->sound;
    }
}

$cat = new Animal('Cat', 'meow');
$dog = new Animal('Dog', 'woof');
echo $cat->speak() . "\n";
echo $dog->speak() . "\n";

// property defaults
class Counter {
    public $count = 0;

    public function inc() {
        $this->count = $this->count + 1;
    }

    public function get() {
        return $this->count;
    }
}

$c = new Counter();
$c->inc();
$c->inc();
$c->inc();
echo $c->get() . "\n";

// multiple instances are independent
$a = new Counter();
$b = new Counter();
$a->inc();
$a->inc();
$b->inc();
echo $a->get() . "\n";
echo $b->get() . "\n";

// method with return value
class Math {
    public function add($a, $b) {
        return $a + $b;
    }

    public function multiply($a, $b) {
        return $a * $b;
    }
}

$m = new Math();
echo $m->add(3, 4) . "\n";
echo $m->multiply(5, 6) . "\n";

// gettype
class Foo {}
$f = new Foo();
echo gettype($f) . "\n";

// property assignment from outside
class Box {
    public $value;

    public function __construct($v) {
        $this->value = $v;
    }
}

$b = new Box(10);
echo $b->value . "\n";
$b->value = 20;
echo $b->value . "\n";
