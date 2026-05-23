<?php
// wp_parse_args, wp_parse_str, wp_list_pluck, wp_list_sort, wp_list_filter,
// _wp_array_get, _wp_array_set - WP's array-shaping helpers used by every
// theme/plugin. pure functions, no DB.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

require $abspath . 'wp-load.php';

echo "== wp_parse_args (array) ==\n";
print_r(wp_parse_args(['b' => 20, 'd' => 40], ['a' => 1, 'b' => 2, 'c' => 3]));

echo "== wp_parse_args (query string) ==\n";
print_r(wp_parse_args('a=10&b=hi&c=&d', ['a' => 1, 'b' => 2, 'c' => 3]));

echo "== wp_parse_args (object) ==\n";
print_r(wp_parse_args((object)['a' => 100, 'x' => 'extra'], ['a' => 1, 'b' => 2]));

echo "== wp_parse_str ==\n";
$out = [];
wp_parse_str('foo=bar&list[]=a&list[]=b&nested[key]=val', $out);
print_r($out);

echo "== wp_list_pluck (string keys) ==\n";
$items = [
    ['id' => 10, 'name' => 'alpha', 'cat' => 'x'],
    ['id' => 20, 'name' => 'beta',  'cat' => 'y'],
    ['id' => 30, 'name' => 'gamma', 'cat' => 'x'],
];
print_r(wp_list_pluck($items, 'name'));
print_r(wp_list_pluck($items, 'name', 'id'));

echo "== wp_list_pluck (objects) ==\n";
$objs = [
    (object)['k' => 'a', 'v' => 1],
    (object)['k' => 'b', 'v' => 2],
];
print_r(wp_list_pluck($objs, 'v', 'k'));

echo "== wp_list_filter (AND) ==\n";
print_r(wp_list_filter($items, ['cat' => 'x']));

echo "== wp_list_sort (single key) ==\n";
$sorted = wp_list_sort($items, 'name');
foreach ($sorted as $s) echo $s['name'], ' ';
echo "\n";

echo "== wp_list_sort (multi key) ==\n";
$multi = [
    ['a' => 1, 'b' => 2],
    ['a' => 1, 'b' => 1],
    ['a' => 2, 'b' => 1],
];
$sorted = wp_list_sort($multi, ['a' => 'ASC', 'b' => 'ASC']);
foreach ($sorted as $s) echo "({$s['a']},{$s['b']}) ";
echo "\n";

echo "== _wp_array_get ==\n";
$nested = ['l1' => ['l2' => ['l3' => 'deep']]];
echo _wp_array_get($nested, ['l1', 'l2', 'l3'], 'default'), "\n";
echo _wp_array_get($nested, ['l1', 'missing'], 'default'), "\n";
echo _wp_array_get($nested, ['nope'], 'fallback'), "\n";

echo "== _wp_array_set ==\n";
$arr = ['existing' => 1];
_wp_array_set($arr, ['a', 'b', 'c'], 'value');
print_r($arr);

echo "== wp_is_numeric_array ==\n";
echo 'list: ', wp_is_numeric_array([1, 2, 3]) ? 'y' : 'n', "\n";
echo 'assoc: ', wp_is_numeric_array(['a' => 1, 'b' => 2]) ? 'y' : 'n', "\n";
echo 'mixed: ', wp_is_numeric_array([0 => 'a', 'b' => 'c']) ? 'y' : 'n', "\n";

echo "done\n";
