<?php
// timelib 2026.03 (php 8.6) keeps 16 errors and 16 warnings and notes the
// rest at position -1
$r = date_parse(str_repeat("@ ", 20));
var_dump($r['error_count'], count($r['errors']));
var_dump(array_slice($r['errors'], -2, 2, true));

$r = date_parse(str_repeat("@ ", 16));
var_dump($r['error_count'], isset($r['errors'][-1]));

$r = date_parse(str_repeat("@ ", 17));
var_dump($r['error_count'], $r['errors'][-1] ?? null);

$r = date_parse_from_format("Y-m-d", str_repeat("x", 3));
var_dump($r['error_count'], $r['errors']);

try {
    new DateTime(str_repeat("@ ", 20));
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
var_dump(date_create(str_repeat("@ ", 20)));
$e = DateTime::getLastErrors();
var_dump($e['error_count'], $e['errors'][-1]);
