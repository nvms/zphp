<?php
ini_set('display_errors', '1');
// trigger_error populates error_get_last
trigger_error("first", E_USER_NOTICE);
$e = error_get_last();
echo $e['type'], " ", $e['message'], "\n";

trigger_error("second", E_USER_WARNING);
$e2 = error_get_last();
echo $e2['type'], " ", $e2['message'], "\n";

// custom handler
$caught = [];
set_error_handler(function($errno, $errstr) use (&$caught) {
    $caught[] = "$errno:$errstr";
    return true;
});
trigger_error("a", E_USER_NOTICE);
trigger_error("b", E_USER_WARNING);
restore_error_handler();
print_r($caught);

// trigger_error returns true
var_dump(trigger_error("x", E_USER_NOTICE));

// E_USER_* constants
echo E_USER_NOTICE, " ", E_USER_WARNING, " ", E_USER_DEPRECATED, "\n";

// DateTimeZone::listIdentifiers
$tz = DateTimeZone::listIdentifiers();
var_dump(is_array($tz));
echo count($tz) > 0 ? "non-empty\n" : "empty\n";
echo in_array('UTC', $tz) ? "has utc\n" : "no utc\n";
echo in_array('America/New_York', $tz) ? "has ny\n" : "no ny\n";
echo in_array('Europe/Paris', $tz) ? "has paris\n" : "no paris\n";
