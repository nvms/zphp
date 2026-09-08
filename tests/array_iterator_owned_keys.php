<?php
function entries() {
    return [str_replace('prefix/', '', 'prefix/one') => 1, str_replace('prefix/', '', 'prefix/two') => 2];
}
$iterator = new ArrayIterator(entries());
for ($i = 0; $i < 3; ++$i) {
    foreach ($iterator as $key => $value) {
        echo $key, ':', $value, "\n";
    }
    gc_collect_cycles();
}
$iterator->rewind();
$key = $iterator->key();
unset($iterator);
gc_collect_cycles();
var_dump($key);
