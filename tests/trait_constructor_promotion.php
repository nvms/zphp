<?php
// a trait's constructor declares its promoted parameters as properties of
// the classes that use it

trait Point {
    public $label = 'p';

    public function __construct(public $x, protected int $y = 0, public readonly ?string $tag = null) {}

    public function y() { return $this->y; }
}

class P {
    use Point;
}

$p = new P(1, 2, 't');
var_dump($p, $p->y());
$r = new ReflectionClass('P');
foreach ($r->getProperties() as $prop) {
    echo $prop->getName(), ' ', $prop->hasType() ? $prop->getType() : '-', ' ', $prop->isReadOnly() ? 'readonly' : '', "\n";
}
try {
    $p->tag = 'u';
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump(get_object_vars(new P('a')));
