<?php
foreach (['current', 'reset', 'end', 'array_pop', 'array_shift'] as $getter) {
    if (!function_exists($getter)) continue;
    $value = 'retained-' . 42;
    $array = [$value];
    $result = $getter($array);
    unset($array, $value);
    gc_collect_cycles();
    var_dump($result);
}
foreach (['key', 'array_key_first', 'array_key_last'] as $getter) {
    $array = ['key-' . 7 => 1];
    $result = $getter($array);
    unset($array);
    gc_collect_cycles();
    var_dump($result);
}
