<?php
// regression: unserialize emits PHP-format warnings on parse failure
// ('Error at offset N of M bytes') and max_depth violation. previously
// zphp returned false silently for both, masking caller bugs
var_dump(unserialize("garbage"));
var_dump(unserialize("not:valid:syntax"));
var_dump(unserialize("i:42;"));   // valid, no warning

// empty input returns false WITHOUT a warning (PHP convention)
var_dump(unserialize(""));

// max_depth exceeded - use a correctly-serialized nested structure
$nested = serialize(['x' => ['y' => 'deep']]);
var_dump(unserialize($nested, ['max_depth' => 1]));

// deep enough budget succeeds
var_dump(unserialize($nested, ['max_depth' => 10]));
