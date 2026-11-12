<?php
// get_resources lists the live resources by id, all or of one type

$before = count(get_resources());
$a = fopen('php://memory', 'r');
$b = fopen('php://memory', 'r');
$ctx = stream_context_create();
$all = get_resources();
var_dump(count($all) - $before);
var_dump(array_search($a, $all, true) === (int) $a, array_search($ctx, $all, true) === (int) $ctx);
var_dump(count(get_resources('stream-context')) >= 1, in_array($b, get_resources('stream'), true));
try {
    get_resources('no such type');
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
unset($b);
var_dump(count(get_resources()) - $before);
fclose($a);
var_dump(in_array($a, get_resources('Unknown'), true));
