<?php

class Animal {
    public $name;
    public $type = "unknown";

    public function speak() { return "..."; }
    public function getName() { return $this->name; }
}

class Dog extends Animal {
    public $breed;

    public function speak() { return "woof"; }
    public function fetch() { return "fetching"; }
}

interface Swimmable {
    public function swim();
}

// get_object_vars
$d = new Dog();
$d->name = "Rex";
$d->breed = "Lab";
$vars = get_object_vars($d);
echo $vars["name"] . "\n";
echo $vars["breed"] . "\n";

// get_class_methods
$methods = get_class_methods("Dog");
sort($methods);
echo implode(",", $methods) . "\n";

// get_parent_class
echo get_parent_class("Dog") . "\n";
echo get_parent_class($d) . "\n";
var_dump(get_parent_class("Animal"));

// is_a
echo is_a($d, "Dog") ? "yes" : "no";
echo "\n";
echo is_a($d, "Animal") ? "yes" : "no";
echo "\n";
echo is_a($d, "Cat") ? "yes" : "no";
echo "\n";

// is_subclass_of
echo is_subclass_of($d, "Animal") ? "yes" : "no";
echo "\n";
echo is_subclass_of($d, "Dog") ? "yes" : "no";
echo "\n";

// spl_object_id
$id1 = spl_object_id($d);
$id2 = spl_object_id(new Dog());
echo ($id1 !== $id2) ? "unique" : "same";
echo "\n";

// get_class_vars
$cv = get_class_vars("Animal");
echo $cv["type"] . "\n";
