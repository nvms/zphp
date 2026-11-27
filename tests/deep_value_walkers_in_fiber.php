<?php
// walkers php doesn't bound by the native stack (print_r, unserialize,
// array_merge_recursive's merge) go as deep as the value, on a fiber's
// stack too
ini_set('fiber.stack_size', '16M');
$fiber = new Fiber(function () {
    $a = [];
    for ($i = 0; $i < 1500; $i++) $a = [$a, $i];
    $printed = print_r($a, true);
    echo "print_r: ", strlen($printed), " bytes, ", substr_count($printed, "Array"), " arrays, ", md5($printed), "\n";

    $o = new stdClass;
    $cur = $o;
    for ($i = 0; $i < 1000; $i++) {
        $cur->next = new stdClass;
        $cur->n = $i;
        $cur = $cur->next;
    }
    $printed = print_r($o, true);
    echo "print_r objects: ", strlen($printed), " bytes, ", md5($printed), "\n";

    $x = [];
    $y = [];
    for ($i = 0; $i < 20000; $i++) {
        $x = ['k' => $x, 'v' => $i];
        $y = ['k' => $y, 'w' => $i];
    }
    $m = array_merge_recursive($x, $y);
    $depth = 0;
    $sum = 0;
    while (isset($m['k'])) {
        $sum += $m['v'] + $m['w'];
        $m = $m['k'];
        $depth++;
    }
    echo "array_merge_recursive: $depth deep, $sum\n";

    // unserialize without a depth limit
    $s = str_repeat('a:1:{i:0;', 20000) . 'a:0:{}' . str_repeat('}', 20000);
    $v = unserialize($s, ['max_depth' => 0]);
    $depth = 0;
    while (is_array($v) && $v !== []) {
        $v = $v[0];
        $depth++;
    }
    echo "unserialize: $depth deep\n";
});
$fiber->start();
