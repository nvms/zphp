<?php
// a destructor or __clone the releasing or cloning scope can't call is not
// run: during the script that is an Error, at shutdown a warning
class Guarded {
    public static $kept;
    private function __clone() {
        echo "clone\n";
    }
    protected function __destruct() {
        echo "destruct\n";
    }
    public static function make() {
        $a = new static;
        $b = clone $a;
        unset($a, $b);
        return new static;
    }
}

$g = Guarded::make();
try {
    $c = clone $g;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
try {
    unset($g);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
Guarded::$kept = Guarded::make();
echo "end of script\n";
