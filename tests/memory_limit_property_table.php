<?php
// an object's dynamic property table counts at php's size, also its huge
// blocks: 128K properties fit under a 16MB limit, as in php
ini_set('memory_limit', '16M');

$o = new stdClass;
for ($i = 0; $i < 128 * 1024 - 1; $i++) {
    $o->{"p$i"} = 0;
}
echo memory_get_usage(true) < 16 * 1024 * 1024 ? "under the limit\n" : "over the limit\n";
var_dump(isset($o->p131070), isset($o->p131071));
unset($o);
echo memory_get_usage() < 1024 * 1024 ? "freed\n" : "kept\n";
