<?php
// debug_backtrace() shows the parameters as they are now, as an exception's
// trace does, extra arguments as they were passed
function changed($x, $y = 'default') {
    $x = 'reassigned';
    var_dump(debug_backtrace()[0]['args']);
}
changed('original');
changed('original', 'given', 'extra');

function variadic($first, ...$rest) {
    $first = 'new';
    var_dump(debug_backtrace()[0]['args']);
}
variadic(1, 2, 3);

class Magic {
    public function __call($name, $args) {
        eval('$args = []; var_dump(debug_backtrace()[1]["args"]);');
        $args = ['set'];
        debug_print_backtrace();
    }
}
(new Magic)->missing('value');

function outer($a) {
    $a = 'outer changed';
    inner();
}
function inner() {
    var_dump(debug_backtrace()[1]['args']);
}
outer('outer original');
