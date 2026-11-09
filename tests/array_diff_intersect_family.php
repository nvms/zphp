<?php
// the array_diff and array_intersect families on everyday data: what keys
// and order survive, how values compare as strings, and the next index of
// the result

$warehouse = ['sku-100' => 12, 'sku-200' => 0, 'sku-300' => 7, 'sku-400' => '7', 'sku-500' => 3.0];
$storefront = ['sku-100' => '12', 'sku-300' => 7, 'sku-400' => 8, 'sku-600' => 1];

echo "-- stock levels that changed --\n";
var_dump(array_diff_assoc($warehouse, $storefront));
echo "-- products missing from the storefront --\n";
var_dump(array_diff_key($warehouse, $storefront));
echo "-- products listed in both --\n";
var_dump(array_intersect_key($warehouse, $storefront));
echo "-- same product and same count --\n";
var_dump(array_intersect_assoc($warehouse, $storefront));

$granted = ['read', 'write', 'delete', 'admin', 'write'];
$revoked = ['admin', 'delete'];
$required = ['read', 'write', 'export'];
echo "-- permissions left after revoking --\n";
var_dump(array_diff($granted, $revoked));
echo "-- required permissions the user holds --\n";
var_dump(array_intersect($required, $granted, ['write', 'read', 'export']));

echo "-- values compare by their string forms --\n";
var_dump(array_diff([1, '1', 1.0, true, '01', null, '', 0, '0', 1.5], ['1', '']));
var_dump(array_intersect([10 => 1.0, 'a' => '1', 'b' => true, 'c' => 0.1 + 0.2], [1, '0.3']));
var_dump(array_diff([-0.0, 0.0, '-0'], [0]));

echo "-- integer keys print as text when compared as keys --\n";
var_dump(array_diff_key([1 => 'a', '01' => 'b', 'x' => 'c'], ['1' => 0]));
var_dump(array_intersect_key(['-0' => 'neg', 0 => 'zero', '1.5' => 'f'], [0 => 1, '-0' => 2]));

echo "-- the next index of each result --\n";
$r = array_diff([5 => 'a', 9 => 'b', 'c'], ['b', 'c']);
$r[] = 'next';
var_dump($r);
$r = array_intersect([5 => 'a', 9 => 'b', 'c'], ['a']);
$r[] = 'next';
var_dump($r);
$r = array_udiff([5 => 'a', 9 => 'b', 'c'], ['b', 'c'], 'strcmp');
$r[] = 'next';
var_dump($r);
$r = array_diff_key([-5 => 'a', -3 => 'b'], [-3 => 1]);
$r[] = 'next';
var_dump($r);
$r = array_diff([7 => 'only'], []);
$r[] = 'next';
var_dump($r);

echo "-- nested arrays and objects become strings --\n";
class Tag
{
    public function __construct(private string $name) {}
    public function __toString(): string
    {
        return $this->name;
    }
}
var_dump(array_diff([new Tag('php'), new Tag('zig'), 'rust'], ['zig', new Tag('rust')]));
var_dump(array_diff(['x', [1], 'y'], ['y']));
var_dump(array_intersect([[1], 'Array', 'z'], ['Array']));

echo "-- references survive when shared --\n";
$data = ['a' => 1, 'b' => 2, 'c' => 3];
$ref = &$data['a'];
var_dump(array_diff($data, [2]));
var_dump(array_intersect_key($data, ['a' => 0, 'c' => 0]));
var_dump(array_udiff_uassoc($data, ['c' => 3], fn($x, $y) => $x <=> $y, fn($x, $y) => strcmp($x, $y)));
unset($ref);

echo "-- user comparisons --\n";
$people = [
    ['id' => 3, 'name' => 'Ana'],
    ['id' => 1, 'name' => 'Ben'],
    ['id' => 7, 'name' => 'Cleo'],
    ['id' => 4, 'name' => 'Dev'],
];
$departed = [['id' => 1], ['id' => 4]];
$byId = fn($a, $b) => $a['id'] <=> $b['id'];
var_dump(array_column(array_udiff($people, $departed, $byId), 'name'));
var_dump(array_column(array_uintersect($people, $departed, $byId), 'name'));
$headersA = ['Content-Type' => 'text/html', 'X-Trace' => 'abc', 'Cache-Control' => 'no-cache'];
$headersB = ['content-type' => 'TEXT/HTML', 'cache-control' => 'max-age=0'];
var_dump(array_diff_ukey($headersA, $headersB, 'strcasecmp'));
var_dump(array_intersect_ukey($headersA, $headersB, 'strcasecmp'));
var_dump(array_diff_uassoc($headersA, $headersB, 'strcasecmp'));
var_dump(array_intersect_uassoc($headersA, ['content-type' => 'text/html'], 'strcasecmp'));
var_dump(array_udiff_assoc($headersA, ['Content-Type' => 'TEXT/HTML'], 'strcasecmp'));
var_dump(array_uintersect_assoc($headersA, ['Content-Type' => 'TEXT/HTML'], 'strcasecmp'));
var_dump(array_uintersect_uassoc($headersA, $headersB, 'strcasecmp', 'strcasecmp'));

echo "-- a single array comes back whole --\n";
var_dump(array_diff(['k' => 'v', 3 => 'w']));
var_dump(array_intersect(['k' => 'v', 3 => 'w']));
var_dump(array_udiff(['k' => 'v'], 'strcmp'));
var_dump(array_intersect_ukey(['k' => 'v'], 'strcmp'));
