<?php
// a constant array naming a property is converted while compiling, so its
// warning comes before anything runs
echo "start\n";
$o = new stdClass;
$o->{[]} = 1;
$o->{array(1, 'a' => -2.5, [true, null])} .= "x";
var_dump(isset($o->{[1]}));
var_dump($o?->{([])});
unset($o->{[2]});
var_dump($o);

// a non-constant array still converts when it runs
$v = 3;
echo "runtime\n";
var_dump($o->{[$v]});

function f($o) {
    return $o->{[1, 2]};
}
echo "call\n";
var_dump(f($o));
