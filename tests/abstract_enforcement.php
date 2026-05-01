<?php

// abstract method must be implemented in concrete subclass
abstract class Animal {
    abstract public function speak(): string;
    public function describe(): string { return "an animal that says " . $this->speak(); }
}

class Dog extends Animal {
    public function speak(): string { return "woof"; }
}
echo (new Dog())->describe() . "\n";

// concrete subclass missing impl - should error at class registration time
// (an uncatchable fatal in PHP, so we test indirectly via reflection on
// a class that exists)
$rc = new ReflectionClass(Animal::class);
echo ($rc->isAbstract() ? "abstract" : "concrete") . "\n";
$rd = new ReflectionClass(Dog::class);
echo ($rd->isAbstract() ? "abstract" : "concrete") . "\n";

// interface methods must be implemented
interface Flyable {
    public function fly(): void;
    public function land(): void;
}

class Plane implements Flyable {
    public function fly(): void { echo "flying "; }
    public function land(): void { echo "landed\n"; }
}
$p = new Plane();
$p->fly();
$p->land();

// abstract subclass can leave methods abstract
abstract class Shape {
    abstract public function area(): float;
    abstract public function perimeter(): float;
}

abstract class Polygon extends Shape {
    // partial - perimeter still abstract
    public function area(): float { return 0.0; }
}

class Square extends Polygon {
    public function __construct(public float $side) {}
    public function perimeter(): float { return 4 * $this->side; }
    public function area(): float { return $this->side * $this->side; }
}
$s = new Square(5);
echo $s->area() . "/" . $s->perimeter() . "\n";

// inherited concrete impl satisfies interface
abstract class HasName {
    public function name(): string { return 'default'; }
}
interface Named { public function name(): string; }
class Thing extends HasName implements Named {}
echo (new Thing())->name() . "\n";
