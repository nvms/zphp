<?php
// operator details: -$a is $a * -1 (a numeric string keeps its type), a
// leading-numeric string divides as the int it starts with, string ^ and &
// stop at the shorter operand, NaN compares false every way, and ~ on a
// float warns when it can't become an int
set_error_handler(function ($no, $msg) {
    echo "[$no] $msg\n";
    return true;
});
var_dump(-"1.2", -"-7.7", -" 1", -"1e3", -"5abc");
foreach ([fn () => -"abc", fn () => -[], fn () => -new stdClass] as $f) {
    try {
        var_dump($f());
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}
var_dump("0" / "123abc", "10" / "5", "7" / "2", "8abc" / "2");
var_dump(bin2hex("0" ^ "65"), bin2hex("abc" ^ "a"), "abc" & "a", "a" | "abc");
$nan = NAN;
$zero = 0;
var_dump($zero < $nan, $zero <= $nan, $zero > $nan, $zero >= $nan, $zero <=> $nan, $nan <=> $zero);
var_dump(1.5 < $nan, 1.5 >= $nan, "1" <= $nan, $nan >= "1");
var_dump(~5, ~23.67, ~9.2233720368548E+18, ~-1.0);
