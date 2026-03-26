<?php

// simple nested
$arr = [];
$arr['a']['b'] = 1;
echo $arr['a']['b'] . "\n";

// nested with push
$arr2 = [];
$arr2['x']['y'][] = 'hello';
echo $arr2['x']['y'][0] . "\n";

// 3-level deep
$arr3 = [];
$arr3['a']['b']['c'] = 5;
echo $arr3['a']['b']['c'] . "\n";

// integer keys
$arr4 = [];
$arr4[0][1][2] = 'x';
echo $arr4[0][1][2] . "\n";

// copy semantics: vivified arrays must not leak across copies
$orig = [];
$orig['a']['b'] = 1;
$copy = $orig;
$orig['a']['c'] = 2;
echo isset($copy['a']['c']) ? "FAIL" : "PASS" . "\n";

// existing intermediate is preserved
$arr5 = [];
$arr5['a'] = ['existing' => 99];
$arr5['a']['b'] = 1;
echo $arr5['a']['existing'] . "\n";
echo $arr5['a']['b'] . "\n";

// compound assignment with vivification
$arr6 = [];
$arr6['a']['b'] = 5;
$arr6['a']['b'] += 3;
echo $arr6['a']['b'] . "\n";

// multiple pushes
$arr7 = [];
$arr7['list'][] = 'a';
$arr7['list'][] = 'b';
$arr7['list'][] = 'c';
echo count($arr7['list']) . "\n";
echo $arr7['list'][1] . "\n";
