<?php
// an assignment to a destructuring pattern or an appended element is the
// right operand of a tighter operator, as php's grammar reads it

namespace Space {
    function hello() { echo "namespace-relative call\n"; }
    namespace\hello();
}

namespace {
    $c = [1, 2];
    $r = true && [$a, $b] = $c;
    var_dump($r, $a, $b);
    $r = false || list($x, $y) = [3, 4];
    var_dump($r, $x, $y);
    $list = [];
    $r = true && $list[] = 5;
    var_dump($r, $list);
    $r = null ?? ['k' => $v] = ['k' => 6];
    var_dump($r, $v);
}
