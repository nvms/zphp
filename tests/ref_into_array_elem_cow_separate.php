<?php

// `$v = &$arr[$k]` makes $arr[$k] a reference, which can't stay COW-shared:
// binding the ref must separate a shared element so a later in-place mutation
// through the ref doesn't corrupt another holder that copied the element
// before the ref was taken. PHP separates at EACH `&` descent level - the
// shape Laravel's Arr::forget uses (`$a = &$a[$part]` chain + unset).

// direct two-level ref into a nested element
$cfg = ['db' => ['conns' => ['sqlite' => 1, 'mysql' => 2]]];
$reader = $cfg['db']['conns'];
$ref = &$cfg['db']['conns'];
unset($ref['mysql']);
echo "direct cfg conns: ", implode(',', array_keys($cfg['db']['conns'])), "\n";  // sqlite
echo "direct reader: ", implode(',', array_keys($reader)), "\n";                 // sqlite,mysql

// chained descent through a by-ref param (the Arr::forget shape)
function forget(array &$array, string $path): void
{
    $parts = explode('.', $path);
    while (count($parts) > 1) {
        $part = array_shift($parts);
        $array = &$array[$part];
    }
    unset($array[array_shift($parts)]);
}

$cfg2 = ['db' => ['conns' => ['sqlite' => 1, 'mysql' => 2], 'default' => 'sqlite']];
$rd = $cfg2['db']['conns'];
forget($cfg2, 'db.conns.mysql');
echo "forget cfg2 conns: ", implode(',', array_keys($cfg2['db']['conns'])), "\n";  // sqlite
echo "forget rd: ", implode(',', array_keys($rd)), "\n";                           // sqlite,mysql
echo "forget cfg2 default (by-ref reached it): ", ($cfg2['db']['default'] ?? 'GONE'), "\n";  // sqlite

// with the $original re-alias dance Laravel actually uses
function forgetReal(array &$array, string $path): void
{
    $original = &$array;
    $parts = explode('.', $path);
    $array = &$original;
    while (count($parts) > 1) {
        $part = array_shift($parts);
        if (isset($array[$part])) {
            $array = &$array[$part];
        }
    }
    unset($array[array_shift($parts)]);
}

$cfg3 = ['a' => ['b' => ['c' => 1, 'd' => 2]]];
$rd3 = $cfg3['a']['b'];
forgetReal($cfg3, 'a.b.c');
echo "forgetReal cfg3 a.b: ", implode(',', array_keys($cfg3['a']['b'])), "\n";  // d
echo "forgetReal rd3: ", implode(',', array_keys($rd3)), "\n";                  // c,d

// a write through the ref (not just unset) must also separate
$src = ['k' => ['x' => 1]];
$cpy = $src['k'];
$r = &$src['k'];
$r['y'] = 2;
echo "write src.k: ", implode(',', array_keys($src['k'])), "\n";  // x,y
echo "write cpy (untouched): ", implode(',', array_keys($cpy)), "\n";  // x
