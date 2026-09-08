<?php
function findThenRemove(): string {
    $values = ['temporary-' . 42 => 7];
    $key = array_search(7, $values, true);
    unset($values[$key]);
    gc_collect_cycles();
    return $key;
}
var_dump(findThenRemove());
