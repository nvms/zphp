<?php
// basic variable variable read
$name = "hello";
$hello = "world";
echo $$name . "\n";

// variable variable write
$$name = "changed";
echo $hello . "\n";

// in function scope
function testLocal() {
    $x = "msg";
    $msg = "from function";
    echo $$x . "\n";

    $$x = "modified";
    echo $msg . "\n";
}
testLocal();

// foreach with variable variables (Carbon's createSafe pattern)
function testForeach($year = null, $month = null, $day = null) {
    $fields = ['year', 'month', 'day'];
    foreach ($fields as $field) {
        $val = $$field;
        if ($val !== null) {
            echo "$field=$val\n";
        } else {
            echo "$field=null\n";
        }
    }
}
testForeach(2024, 6, null);

// variable variable with assignment in loop
function testAssign() {
    $vars = ['a', 'b', 'c'];
    foreach ($vars as $v) {
        $$v = strtoupper($v);
    }
    echo "$a $b $c\n";
}
testAssign();

// nested: $$$var
$x = "y";
$y = "z";
$z = "final";
echo $$$x . "\n";
