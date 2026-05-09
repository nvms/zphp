<?php
// circular self
$a = new stdClass;
$a->self = $a;
$out = @var_export($a, true);
echo strpos($out, 'NULL') !== false ? "self ok\n" : "self missing\n";
var_dump($out);

// circular array
$arr = [1, 2];
$arr['self'] = &$arr;
$out = @var_export($arr, true);
echo strpos($out, 'NULL') !== false ? "arr ok\n" : "arr missing\n";

// non-circular still works
echo var_export(['x' => ['y' => 1]], true), "\n";
echo var_export(['a' => 1, 'b' => [2, 3]], true), "\n";

// json_encode with circular returns false + sets error
$b = new stdClass;
$b->self = $b;
var_dump(@json_encode($b));
echo json_last_error_msg(), "\n";

// json_encode circular array
$arr2 = ['x' => 1];
$arr2['self'] = &$arr2;
var_dump(@json_encode($arr2));
echo json_last_error_msg(), "\n";

// JSON_THROW_ON_ERROR with cycle
$c = new stdClass;
$c->self = $c;
try {
    json_encode($c, JSON_THROW_ON_ERROR);
} catch (\JsonException $e) {
    echo "caught: ", $e->getMessage(), "\n";
}

// json_encode shared (non-circular) refs - works
$shared = new stdClass; $shared->v = 'sh';
$wrap = ['a' => $shared, 'b' => $shared];
echo json_encode($wrap), "\n";

// json_encode resets error between calls
@json_encode((function() { $x = new stdClass; $x->self = $x; return $x; })());
$ok = json_encode(['x' => 1]);
echo "second: $ok\n";
echo "after: ", json_last_error(), "\n";
