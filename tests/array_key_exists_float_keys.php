<?php
// array_key_exists() converts a float key as an array offset does: one past
// the int range warns and is cast modulo 2^64
$a = [0 => 'zero', 1 => 'one', -1 => 'minus'];
foreach ([1.0, -1.0, 1e42, -1e19, 2.0 ** 64 + 2048.0, INF] as $k) {
    var_dump(array_key_exists($k, $a));
    var_dump(isset($a[$k]));
    var_dump(key_exists($k, $a));
}
