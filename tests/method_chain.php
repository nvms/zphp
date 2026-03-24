<?php

class Builder {
    private $parts = [];

    public function add($part) {
        $this->parts[] = $part;
        return $this;
    }

    public function build() {
        return implode(" ", $this->parts);
    }
}

$result = (new Builder())->add("hello")->add("world")->build();
echo $result . "\n";

// chaining with different return types mid-chain
class Counter {
    private $n = 0;

    public function inc() {
        $this->n++;
        return $this;
    }

    public function get() {
        return $this->n;
    }
}

$c = new Counter();
echo $c->inc()->inc()->inc()->get() . "\n";

// method chain where method returns a different object
class Wrapper {
    private $inner;

    public function __construct($inner) {
        $this->inner = $inner;
    }

    public function unwrap() {
        return $this->inner;
    }
}

class Value2 {
    public $val;

    public function __construct($val) {
        $this->val = $val;
    }
}

$w = new Wrapper(new Value2(42));
echo $w->unwrap()->val . "\n";
