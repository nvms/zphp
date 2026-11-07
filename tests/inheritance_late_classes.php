<?php
// a subclass whose method types name classes not declared yet is declared
// where it stands, so its compatibility check sees what ran before it; a
// class alias counts as the class it names
require __DIR__ . '/include/declarations/shapes.php';

class Factory {
    public function make(): Shape { return new Shape; }
    public function accept(Shape $s): void {}
}
class CircleFactory extends Factory {
    public function make(): Circle { return new Circle; }
}
echo get_class((new CircleFactory)->make()), "\n";

class_alias('Shape', 'Form');
eval('class AliasedFactory extends Factory { public function accept(Form $s): void {} }');
echo "alias accepted\n";

abstract class Walker implements Traversable {}
class Lists { public function walk(): iterable|int { return []; } }
class Walks extends Lists { public function walk(): (Missing&Walker)|int { return 0; } }
echo "intersection resolved by its known member\n";
