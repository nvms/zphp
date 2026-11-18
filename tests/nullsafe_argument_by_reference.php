<?php
// a nullsafe chain passed as an argument is a value: a by-reference
// parameter refuses it, whether the chain ran or was cut short

class Box {
    public $item = 'x';
    public $list = [3, 1, 2];
    public ?Box $inner = null;
    public function get() { return $this->list; }
}

function set(&$ref, $value) {
    $ref = $value;
}

function show($value) {
    var_dump($value);
}

foreach ([null, new Box] as $box) {
    try {
        set($box?->item, 'changed');
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
    try {
        sort($box?->list);
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
    try {
        set($box?->inner->item, 'deep');
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
    show($box?->item);
    show($box?->get());
    var_dump($box);
}
