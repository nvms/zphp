<?php
// a DateInterval that holds itself is not caught as recursion by
// json_encode (each visit gets a fresh property table), so the encoding
// runs until the depth gives out; a cycle through an array is still caught
function show($v) {
    var_dump(json_encode($v));
    var_dump(json_last_error_msg());
}

$a = new DateInterval('P1W');
$a->self = $a;
show($a);

$b = new DateInterval('P1D');
$b->list = [$b];
show($b);

$c = new DateInterval('PT1H');
$d = new DateInterval('PT2H');
$c->other = $d;
$d->other = $c;
show($c);

class MyInterval extends DateInterval {}
$e = new MyInterval('P2D');
$e->self = $e;
show($e);

// other objects are still caught at once
$o = new stdClass();
$o->self = $o;
show($o);
var_dump(json_encode($o, JSON_PARTIAL_OUTPUT_ON_ERROR));

// nothing is left marked: the same interval encodes cleanly afterwards
unset($a->self);
show($a);
show([$a, $a]);
