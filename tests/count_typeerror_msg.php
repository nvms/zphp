<?php
// regression: count() TypeError includes the PHP-format type name of the
// rejected value: "..., <type> given" where <type> is one of null, true,
// false, int, float, string, array, or the class name for objects.
// previously zphp emitted the message without the trailing type
foreach (["str", 42, 3.14, true, false, null, new stdClass(), function() {}] as $v) {
    try {
        count($v);
        echo "no-throw\n";
    } catch (\TypeError $e) {
        echo $e->getMessage() . "\n";
    }
}
