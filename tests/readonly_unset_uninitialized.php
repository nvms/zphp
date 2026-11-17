<?php
// an uninitialized readonly property may be unset in its class (so __get
// can initialize it lazily), even twice; one holding a value, null
// included, may not
class Lazy {
    public readonly int $prop;

    public function __construct() {
        unset($this->prop);
        unset($this->prop);
    }

    public function __get($name) {
        echo __METHOD__, "\n";
        $this->prop = 1;
        return $this->prop;
    }
}

$lazy = new Lazy;
var_dump($lazy->prop, $lazy->prop);
try {
    unset($lazy->prop);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

class Nullable {
    public readonly ?int $prop;

    public function __construct() {
        $this->prop = null;
        try {
            unset($this->prop);
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
    }
}
var_dump(new Nullable);
