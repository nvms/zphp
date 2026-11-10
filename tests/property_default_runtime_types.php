<?php
// a property default php evaluates when the class is first used must fit
// the property's type exactly; the next use tries again

define("FIVE", 5);
const TEXT = "text";

class Ints { public int $n = FIVE; public float $f = FIVE; public static float $s = FIVE; }
class Strings { public string $s = FIVE; }
class Statics { public static string $s = FIVE; }
class Nullable { public ?int $n = TEXT; }

$o = new Ints;
var_dump($o->n, $o->f, Ints::$s);
for ($i = 0; $i < 2; $i++) {
    try {
        var_dump((new Strings)->s);
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}
try {
    var_dump(Statics::$s);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    var_dump(new Nullable);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
