<?php

abstract class Animal {
    public $name;

    public function __construct($name) {
        $this->name = $name;
    }

    abstract public function speak();

    public function describe() {
        return $this->name . " says " . $this->speak();
    }
}

class Dog extends Animal {
    public function speak() {
        return "woof";
    }
}

class Cat extends Animal {
    public function speak() {
        return "meow";
    }
}

$d = new Dog("Rex");
echo $d->describe() . "\n";
echo $d->speak() . "\n";

$c = new Cat("Whiskers");
echo $c->describe() . "\n";

echo ($d instanceof Animal) ? "true" : "false";
echo "\n";

// abstract with interface
interface Countable2 {
    public function count2();
}

abstract class Collection implements Countable2 {
    abstract public function items();
}

class SimpleList extends Collection {
    private $data;

    public function __construct($data) {
        $this->data = $data;
    }

    public function items() {
        return $this->data;
    }

    public function count2() {
        return count($this->data);
    }
}

$list = new SimpleList([1, 2, 3]);
echo $list->count2() . "\n";
echo ($list instanceof Collection) ? "true" : "false";
echo "\n";
echo ($list instanceof Countable2) ? "true" : "false";
echo "\n";
