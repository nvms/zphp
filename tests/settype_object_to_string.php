<?php
// settype() to string on an object php can't convert throws, and leaves
// the variable an empty string
$var = new stdClass;
try {
    settype($var, "string");
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump($var);

class S { function __toString(): string { return "text"; } }
$var = new S;
var_dump(settype($var, "string"), $var);
