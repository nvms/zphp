<?php

class Animal {
    public $name;
    public function __construct($name) {
        $this->name = $name;
    }
}

class Dog extends Animal {}
class Cat extends Animal {}

$dog = new Dog("Rex");
$cat = new Cat("Whiskers");

echo ($dog instanceof Dog) ? "true" : "false";
echo "\n";
echo ($dog instanceof Animal) ? "true" : "false";
echo "\n";
echo ($dog instanceof Cat) ? "true" : "false";
echo "\n";
echo ($cat instanceof Cat) ? "true" : "false";
echo "\n";
echo ($cat instanceof Animal) ? "true" : "false";
echo "\n";

// non-object
$x = "hello";
echo ($x instanceof Animal) ? "true" : "false";
echo "\n";

// use in conditionals
if ($dog instanceof Animal) {
    echo "dog is animal\n";
}

if (!($dog instanceof Cat)) {
    echo "dog is not cat\n";
}

// with inheritance chain
class GuideDog extends Dog {}
$guide = new GuideDog("Buddy");
echo ($guide instanceof GuideDog) ? "true" : "false";
echo "\n";
echo ($guide instanceof Dog) ? "true" : "false";
echo "\n";
echo ($guide instanceof Animal) ? "true" : "false";
echo "\n";
