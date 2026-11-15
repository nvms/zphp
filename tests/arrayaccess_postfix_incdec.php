<?php
// $obj[k]++ and $obj[k]-- on an ArrayAccess object step offsetGet's value as
// a temporary after php's notice: an array there can't be stepped, a null
// warns on decrement, and offsetSet never runs

set_error_handler(function ($no, $msg) {
    echo "handler: $msg\n";
    return true;
});

class Box implements ArrayAccess {
    public function __construct(public mixed $value) {}
    public function offsetGet($k): mixed { echo "offsetGet($k)\n"; return $this->value; }
    public function offsetSet($k, $v): void { echo "offsetSet\n"; }
    public function offsetExists($k): bool { return true; }
    public function offsetUnset($k): void {}
}

foreach ([[1, 2], 5, null, "a", 1.5, true] as $value) {
    $box = new Box($value);
    foreach (['inc', 'dec'] as $op) {
        try {
            $old = $op === 'inc' ? $box[0]++ : $box[0]--;
            var_dump($old);
        } catch (TypeError $e) {
            echo get_class($e), ": ", $e->getMessage(), "\n";
        }
    }
}
