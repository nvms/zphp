<?php

trait Greetable {
    public function greet() {
        return "Hello, " . $this->name;
    }
}

trait Farewell {
    public function bye() {
        return "Goodbye, " . $this->name;
    }
}

class Person {
    use Greetable, Farewell;

    public $name;

    public function __construct($name) {
        $this->name = $name;
    }
}

$p = new Person("Bob");
echo $p->greet() . "\n";
echo $p->bye() . "\n";

// trait with method override
trait HasDefault {
    public function value() {
        return "default";
    }
}

class Custom {
    use HasDefault;

    public function value() {
        return "custom";
    }
}

$c = new Custom();
echo $c->value() . "\n";

// multiple classes using same trait
class Robot {
    use Greetable;

    public $name;

    public function __construct($name) {
        $this->name = $name;
    }
}

$r = new Robot("R2D2");
echo $r->greet() . "\n";

// trait with static method
trait Counter {
    public static function describe() {
        return "I am a counter";
    }
}

class MyCounter {
    use Counter;
}

echo MyCounter::describe() . "\n";
