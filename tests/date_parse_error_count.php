<?php
// date_parse() and date_get_last_errors() report every error and warning,
// keyed by position

foreach ([1, 2, 20, 300] as $n) {
    $r = date_parse(str_repeat("\x01", $n));
    echo $n, " ", count($r['errors']), " ", $r['error_count'], " ", count($r['warnings']), "\n";
}
$r = date_parse(str_repeat("x", 40));
echo count($r['errors']), " ", $r['error_count'], "\n";
try {
    new DateTime(str_repeat("@", 50));
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
$e = date_get_last_errors();
echo $e['error_count'], " ", count($e['errors']), " ", $e['warning_count'], "\n";
var_dump(date_create("2021-02-30 25:61"), date_get_last_errors());
