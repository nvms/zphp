<?php
// a float string in a bitwise operation or % is capped to the int range,
// which is deprecated as losing precision, never the out-of-range warning
// a float gets

set_error_handler(function ($errno, $errstr) {
    echo "[$errno] $errstr\n";
    return true;
});

var_dump("1.0E+41" | 1);
var_dump("-1.0E+41" | 1);
var_dump("1.5" | 1);
var_dump("1e1000" | 1);
var_dump(1e41 | 1);
var_dump("1.0E+41" % 7);
var_dump("9.2233720368547758E+18" & 1);
var_dump("1.0E+41" << 1);
