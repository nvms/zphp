<?php
class MutationBox {
    public private(set) array $items = [];
    public private(set) int $number = 1;
    public private(set) string $text;
    public readonly object $object;
    public private(set) object $restricted;
    public readonly int $uninitialized;
    public function __construct() {
        $this->object = new stdClass;
        $this->restricted = new stdClass;
    }
    public function legal() {
        $r =& $this->number;
        $r++;
        $this->items[] = 4;
        unset($this->text);
    }
    public function __set($name, $value) { echo "magic set $name\n"; }
    public function __unset($name) { echo "magic unset $name\n"; }
}
function attempt($fn) {
    try { $fn(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
}
$b = new MutationBox;
attempt(function () use ($b) { $r =& $b->number; $r = 99; });
attempt(function () use ($b) { $name = 'number'; $r =& $b->$name; });
attempt(function () use ($b) { $b->items[] = 2; });
attempt(function () use ($b) { $b->items['x'] = 3; });
attempt(function () use ($b) { $name = 'items'; $b->$name[] = 2; });
attempt(function () use ($b) { $b->text = 'denied'; });
attempt(function () use ($b) { unset($b->text); });
attempt(function () use ($b) { $name = 'text'; unset($b->$name); });
attempt(function () use ($b) { $b->uninitialized = 5; });
$b->object->value = 10;
$b->restricted->value = 20;
$b->legal();
$b->text = 'magic';
unset($b->text);
var_dump($b->number, $b->items, $b->object->value, $b->restricted->value);
