<?php
// hook declarations php accepts: a default on a property a hook reads, a
// wider set parameter type, abstract and interface hooks, final hooks
interface Named { public string $name { get; } }
abstract class Shape implements Named {
    abstract public string $label { get; }
    public string $name { final get => 'shape ' . $this->label; }
}
class Square extends Shape {
    public string $label { get => 'square'; }
    public int $side = 2 {
        get => $this->side;
        set(int|string $value) { $this->side = (int) $value; }
    }
    public $plain = 'kept' { get => $this->plain . '!'; }
}
$s = new Square;
$s->side = '7';
var_dump($s->name, $s->side, $s->plain);
