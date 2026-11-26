<?php
// mbstring's encoding settings default to null and deprecate any new value
set_error_handler(function ($no, $msg) {
    echo "$no: $msg\n";
    return true;
});
foreach (['mbstring.detect_order', 'mbstring.http_input', 'mbstring.http_output', 'mbstring.internal_encoding', 'mbstring.substitute_character'] as $n) {
    var_dump(ini_get($n), ini_get_all('mbstring')[$n]['global_value']);
}
var_dump(ini_set('mbstring.internal_encoding', 'UTF-8'), ini_get('mbstring.internal_encoding'));
var_dump(ini_set('mbstring.http_input', ''));
var_dump(ini_set('mbstring.http_output', 'UTF-8'), ini_get('mbstring.http_output'));
var_dump(ini_set('mbstring.substitute_character', '63'));
var_dump(ini_set('mbstring.detect_order', 'UTF-8'));
var_dump(htmlentities('ä'));
