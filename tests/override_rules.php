<?php
// #[\Override] is met by a parent's non-private method, an interface's,
// an abstract constructor and a trait's abstract method
abstract class Shape {
    abstract public function __construct(int $size);
    public function area(): int { return 0; }
    protected function label(): string { return 'shape'; }
}
interface Named {
    public function name(): string;
}
trait NeedsColor {
    abstract public function color(): string;
}
final class Square extends Shape implements Named {
    use NeedsColor;
    #[\Override]
    public function __construct(private int $size) {}
    #[\Override]
    public function area(): int { return $this->size ** 2; }
    #[\Override]
    protected function label(): string { return 'square'; }
    #[\Override]
    public function name(): string { return $this->label(); }
    #[\Override]
    public function color(): string { return 'red'; }
}
$s = new Square(3);
echo $s->name(), ' ', $s->area(), ' ', $s->color(), "\n";

enum Suit implements Named {
    case Hearts;
    #[\Override]
    public function name(): string { return $this->name; }
}
echo Suit::Hearts->name(), "\n";
