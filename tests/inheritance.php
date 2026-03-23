<?php

// basic inheritance - method and constructor
class Animal {
    public $name;
    public function __construct($name) {
        $this->name = $name;
    }
    public function speak() {
        return $this->name . ' makes a sound';
    }
}

class Dog extends Animal {
    public function speak() {
        return $this->name . ' barks';
    }
}

class Cat extends Animal {}

$d = new Dog('Rex');
$c = new Cat('Whiskers');
echo $d->speak() . "\n";
echo $c->speak() . "\n";
echo $d->name . "\n";
echo $c->name . "\n";

// parent::__construct
class Shape {
    public $color;
    public function __construct($color) {
        $this->color = $color;
    }
}

class Circle extends Shape {
    public $radius;
    public function __construct($color, $radius) {
        parent::__construct($color);
        $this->radius = $radius;
    }
    public function describe() {
        return $this->color . ' circle r=' . $this->radius;
    }
}

$c = new Circle('red', 5);
echo $c->describe() . "\n";

// parent::method()
class Logger {
    public function format($msg) {
        return '[LOG] ' . $msg;
    }
}

class TimedLogger extends Logger {
    public function format($msg) {
        return parent::format($msg) . ' @now';
    }
}

$l = new TimedLogger();
echo $l->format('hello') . "\n";

// three levels of inheritance
class A {
    public function chain() { return 'A'; }
}
class B extends A {
    public function chain() { return parent::chain() . 'B'; }
}
class C extends B {
    public function chain() { return parent::chain() . 'C'; }
}

$obj = new C();
echo $obj->chain() . "\n";

// inherited property defaults
class BaseConfig {
    public $debug = 0;
    public $version = 1;
}

class AppConfig extends BaseConfig {
    public $name = 'myapp';
}

$cfg = new AppConfig();
echo $cfg->debug . "\n";
echo $cfg->version . "\n";
echo $cfg->name . "\n";

// child override of property default
class Parent2 {
    public $x = 10;
}
class Child2 extends Parent2 {
    public $x = 20;
}
$p = new Parent2();
$c2 = new Child2();
echo $p->x . "\n";
echo $c2->x . "\n";
