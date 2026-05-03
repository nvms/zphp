<?php

// PHP 8: when both strings are numeric, compare numerically (== and <=>)
var_dump('1' == '01');
var_dump('1' == '1.0');
var_dump('10' == '1e1');
var_dump('100' == '1e2');
var_dump('0' == '0.0');
var_dump('-0' == '0');
echo ('1' <=> '01') . "\n";
echo ('1' <=> '1.0') . "\n";
echo ('10' <=> '9') . "\n";
echo ('9' <=> '10') . "\n";

// non-numeric strings still byte-compared
var_dump('abc' == 'abc');
var_dump('abc' == 'abd');
echo ('abc' <=> 'abd') . "\n";

// mixed: one numeric one not
var_dump('1' == '1abc');     // both byte-compared (1abc isn't fully numeric)
var_dump('1' == '01abc');

// in_array, array_search use loose equality
var_dump(in_array('01', ['1', '2']));
var_dump(in_array('1.0', ['1.00', '2']));
var_dump(array_search('01', ['x', '1', 'y']));

// max/min on numeric-string arrays compare numerically
var_dump(max(['10', '9', '5']));
var_dump(min(['10', '9', '5']));
var_dump(max(['1.5', '0.9', '20']));
var_dump(min(['1.5', '0.9', '20']));

// sort('1','01','10','2') as strings vs numerics
$arr = ['1', '01', '10', '2'];
sort($arr); // SORT_REGULAR: numeric compare since all numeric strings
print_r($arr);

// array_unique with SORT_REGULAR dedupes '01' and '1'
print_r(array_unique(['1', '01', '2', '02', '1.0']));
