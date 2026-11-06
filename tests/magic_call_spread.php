<?php
// a spread call to a method the class doesn't have goes to __call, as a
// plain call does

class Magic {
    function __call($name, $args) { return "$name(" . implode(",", $args) . ")"; }
}
$m = new Magic;
echo $m->missing(...[1, 2, 3]), "\n";
echo $m->missing(...range(1, 20)), "\n";
echo $m->missing(1, ...[2, 3]), "\n";

class Plain {}
try {
    (new Plain)->nope(...[1]);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
