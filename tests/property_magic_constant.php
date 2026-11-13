<?php
// __PROPERTY__ names the property inside its hooks, and is empty elsewhere
// (a closure inside a hook included)

class Test {
    public $prop {
        get => __PROPERTY__;
        set { var_dump(__PROPERTY__); }
    }

    private $privProp {
        get => __PROPERTY__;
    }

    public $nested {
        get => (function () {
            return __PROPERTY__;
        })();
    }

    public function test() {
        var_dump(__PROPERTY__);
        var_dump($this->privProp);
    }
}

$test = new Test;
var_dump($test->prop);
$test->prop = 'foo';
$test->test();
var_dump($test->nested);
var_dump(__PROPERTY__);
function f() { return __PROPERTY__; }
var_dump(f());
