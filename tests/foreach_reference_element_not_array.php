<?php
// a by-reference foreach over an array element fetches the element for
// writing without making it an array: anything else is refused by the loop
$a = ['f' => false, 'i' => 5, 's' => 'str', 'n' => null];
foreach (['f', 'i', 's', 'n', 'missing' . 1] as $k) {
    foreach ($a[$k] as &$v) {
        echo "never\n";
    }
}
var_dump($a);
$a = ['o' => new ArrayObject([1, 2]), 'arr' => [1, 2]];
foreach ($a['o'] as &$v) {
    $v *= 10;
}
unset($v);
foreach ($a['arr'] as &$v) {
    $v *= 10;
}
unset($v);
var_dump($a);
