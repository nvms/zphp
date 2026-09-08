<?php
function concatenate(): array {
    $s = 'start-' . 1;
    $copy = $s;
    $values = [$s];
    $s .= '-next';
    $s .= $s;
    $values[] = $s;
    $alias = &$s;
    $alias .= '-reference';
    return [$copy, $values, $s, static fn() => $s];
}
[$copy, $values, $s, $closure] = concatenate();
gc_collect_cycles();
var_dump($copy, $values, $s, $closure());
$s = 'x' . 1;
$prefix = substr($s, 0, 1);
for ($i = 0; $i < 100; ++$i) $s .= 'abc';
var_dump($prefix, strlen($s));
