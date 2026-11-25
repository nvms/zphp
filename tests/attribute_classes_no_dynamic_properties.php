<?php
// php's attribute classes refuse dynamic properties (strict-properties in
// their stubs), as other final internal classes do
set_error_handler(function ($no, $msg) { echo "handler: $msg\n"; return true; });

foreach (['SensitiveParameter', 'Override', 'Deprecated', 'NoDiscard', 'DelayedTargetValidation', 'AllowDynamicProperties', 'Attribute'] as $class) {
    try {
        $o = new $class();
        $o->dynamic = 1;
        echo "$class: allowed\n";
    } catch (Error $e) {
        echo "$class: ", $e->getMessage(), "\n";
    }
}
