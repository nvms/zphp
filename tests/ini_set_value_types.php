<?php
declare(strict_types=1);
// ini_set takes a string, int, float, bool or null as the value, even in a
// strict file, and refuses anything else before it looks at the name
var_dump(ini_set('docref_root', null), ini_get('docref_root'));
var_dump(ini_set('html_errors', true), ini_get('html_errors'));
var_dump(ini_set('html_errors', false), ini_get('html_errors'));
var_dump(ini_set('precision', 6), ini_get('precision'));
var_dump(ini_set('user_agent', 3.14), ini_get('user_agent'));
foreach ([[], new stdClass, fopen('php://memory', 'r')] as $bad) {
    try {
        ini_set('no_such_directive', $bad);
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}
var_dump(ini_set('no_such_directive', 'x'));
