<?php
abstract class Shape {
    abstract public function area(): float;
    public function describe(): string {
        return "shape with area " . $this->area();
    }
}

class Circle extends Shape {
    public function __construct(public float $r) {}
    public function area(): float { return M_PI * $this->r ** 2; }
}

class Square extends Shape {
    public function __construct(public float $s) {}
    public function area(): float { return $this->s ** 2; }
}

echo round((new Circle(1.0))->area(), 4), "\n";
echo (new Square(3.0))->area(), "\n";
echo (new Square(2.0))->describe(), "\n";

try {
    $s = new Shape;
    echo "no\n";
} catch (\Error $e) {
    echo "abstract\n";
}

interface Drawable {
    public function draw(): string;
}

class Triangle implements Drawable {
    public function draw(): string { return "triangle"; }
}

echo (new Triangle)->draw(), "\n";
echo (new Triangle) instanceof Drawable ? "y" : "n", "\n";

interface Renderable {
    public function render(): string;
}
interface Describable {
    public function describe(): string;
}

class Widget implements Renderable, Describable {
    public function render(): string { return "render"; }
    public function describe(): string { return "describe"; }
}

$w = new Widget;
echo $w instanceof Renderable && $w instanceof Describable ? "y" : "n", "\n";

final class Sealed {
    public function method(): string { return "sealed"; }
}

echo (new Sealed)->method(), "\n";

class Base {
    public final function finalMethod(): string { return "final"; }
    public function open(): string { return "open"; }
}

class Sub extends Base {
    public function open(): string { return "sub-open"; }
}

echo (new Sub)->finalMethod(), "\n";
echo (new Sub)->open(), "\n";

class Parent1 {
    public static function make(): static {
        return new static;
    }
    public static function className(): string {
        return static::class;
    }
}

class Child1 extends Parent1 {}

echo get_class(Parent1::make()), "\n";
echo get_class(Child1::make()), "\n";
echo Parent1::className(), "\n";
echo Child1::className(), "\n";

class Animal {
    public function __construct(public string $name) {}
    public static function create(string $n): static {
        return new static($n);
    }
}

class Dog extends Animal {}

$a = Animal::create("Generic");
$d = Dog::create("Rex");
echo get_class($a), " ", $a->name, "\n";
echo get_class($d), " ", $d->name, "\n";

abstract class Base2 {
    abstract public function impl(): int;
    public function doubled(): int { return $this->impl() * 2; }
}

class C1 extends Base2 {
    public function impl(): int { return 5; }
}
class C2 extends Base2 {
    public function impl(): int { return 10; }
}

echo (new C1)->doubled(), " ", (new C2)->doubled(), "\n";

class Strable {
    public function __toString(): string { return "stringable"; }
}

$s = new Strable;
echo "$s\n";
echo (string)$s, "\n";

interface Named {
    public function getName(): string;
}

class Pet implements Named {
    public function __construct(public string $name) {}
    public function getName(): string { return $this->name; }
}

function greet(Named $n): string { return "hello, " . $n->getName(); }
echo greet(new Pet("Rex")), "\n";

abstract class Animal2 {
    abstract public function sound(): string;
    public function describe(): string { return "I say " . $this->sound(); }
}

abstract class Mammal extends Animal2 {
    public function fur(): string { return "has fur"; }
}

class Cat2 extends Mammal {
    public function sound(): string { return "meow"; }
}

echo (new Cat2)->describe(), "\n";
echo (new Cat2)->fur(), "\n";

interface Container {
    public function items(): array;
}

abstract class Base3 implements Container {
    public function count(): int { return count($this->items()); }
}

class MyContainer extends Base3 {
    public function __construct(private array $arr) {}
    public function items(): array { return $this->arr; }
}

$c = new MyContainer([1, 2, 3]);
echo $c->count(), "\n";
print_r($c->items());

class Wrapper {
    public static function create(int $v): static {
        $o = new static;
        $o->val = $v;
        return $o;
    }
    public int $val = 0;
}

class WrapperExt extends Wrapper {
    public string $extra = "ext";
}

$w = WrapperExt::create(42);
echo get_class($w), " ", $w->val, " ", $w->extra, "\n";

interface Hashable {
    public function hash(): string;
}

class StringHash implements Hashable {
    public function __construct(public string $value) {}
    public function hash(): string { return md5($this->value); }
}

$h = new StringHash("hello");
echo $h instanceof Hashable ? "y" : "n", "\n";
echo strlen($h->hash()), "\n";

class Container2 implements Container, Hashable {
    public function items(): array { return [1, 2, 3]; }
    public function hash(): string { return "static-hash"; }
}

$c = new Container2;
echo $c->hash(), "\n";
echo count($c->items()), "\n";

abstract class Builder {
    abstract protected function build(): string;
    public function go(): string { return $this->build(); }
}

class MyBuilder extends Builder {
    protected function build(): string { return "built"; }
}

echo (new MyBuilder)->go(), "\n";
