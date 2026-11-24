<?php
// php 8.6 compiles printf() with a literal format of plain %s and %d into an
// echo of the interpolated string, as it already did for sprintf(): no printf
// frame in traces, constants converted while compiling
class Loud {
    public function __toString(): string {
        echo "[", (new Exception)->getTraceAsString(), "]\n";
        return "loud";
    }
}
$n = printf("%s and %d%%\n", new Loud, "12abc");
var_dump($n);
var_dump(printf("plain\n"));
var_dump(printf(""));
$r = printf("%s-%s\n", 1.5, true);
var_dump($r);

class Thrower {
    public function __toString(): string { throw new RuntimeException("no"); }
}
try {
    printf("a %s b %s\n", "x", new Thrower);
} catch (RuntimeException $e) {
    echo "caught ", $e->getMessage(), "\n";
    echo $e->getTraceAsString(), "\n";
}
// not compiled: other specifiers, a count mismatch, a variable format
printf("%05d|%s\n", 42, "z");
try {
    printf("%s %s\n", "only one");
} catch (ArgumentCountError $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
$f = "%s!\n";
printf($f, "var");
ini_set('precision', 3);
printf("%s %s\n", M_PI, 1/3);
echo sprintf("%s|%s", 2.25 * 2, -0.0), "\n";
