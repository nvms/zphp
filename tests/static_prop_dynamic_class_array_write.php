<?php
// an element write through a static property whose class is a variable
// writes the property itself

class C {
    public static $list = [];
    public static $map = null;
    private static $hidden = [];

    function add($v) {
        $this::$hidden[] = $v;
        return self::$hidden;
    }
}

$c = new C;
$c::$list[] = 1;
$c::$list[] = 2;
$name = 'C';
$name::$list['k'] = 3;
$name::$map['a']['b'] = 4;
$c::$list['k'] .= 'x';
var_dump(C::$list, C::$map);
$c->add(5);
var_dump($c->add(6));

try {
    $name::$missing[] = 1;
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
try {
    $c::$hidden[] = 1;
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
