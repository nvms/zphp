<?php
$tests = [
    "abc",
    "ABC",
    "AbC",
    "123",
    "abc123",
    "a",
    "A",
    "1",
    " ",
    "",
    "!",
    "?@!",
    " ab ",
    "\t\n",
    "abc def",
    "  ",
    "\x01\x02\x03",
    "\x7f",
    "0123456789",
    "abcdefABCDEF",
    "0xff",
    "+-=",
];

foreach ($tests as $s) {
    $label = var_export($s, true);
    echo $label, " A=", ctype_alpha($s) ? "y" : "n", " N=", ctype_alnum($s) ? "y" : "n";
    echo " D=", ctype_digit($s) ? "y" : "n", " U=", ctype_upper($s) ? "y" : "n";
    echo " L=", ctype_lower($s) ? "y" : "n", " S=", ctype_space($s) ? "y" : "n";
    echo " P=", ctype_punct($s) ? "y" : "n", " R=", ctype_print($s) ? "y" : "n";
    echo " X=", ctype_xdigit($s) ? "y" : "n", " C=", ctype_cntrl($s) ? "y" : "n";
    echo " G=", ctype_graph($s) ? "y" : "n";
    echo "\n";
}

echo ctype_alpha("Hello"), "\n";
var_dump(ctype_alpha("Hello"));
var_dump(ctype_alpha(""));
var_dump(ctype_digit("0"));
var_dump(ctype_digit("01"));
var_dump(ctype_digit("0.5"));

echo ctype_lower("abc") ? "y" : "n", "\n";
echo ctype_lower("aBc") ? "y" : "n", "\n";
echo ctype_lower("") ? "y" : "n", "\n";

echo ctype_upper("ABC") ? "y" : "n", "\n";
echo ctype_upper("ABc") ? "y" : "n", "\n";
echo ctype_upper("") ? "y" : "n", "\n";

echo ctype_alnum("abc123") ? "y" : "n", "\n";
echo ctype_alnum("abc 123") ? "y" : "n", "\n";

echo ctype_digit("123") ? "y" : "n", "\n";
echo ctype_digit("123.45") ? "y" : "n", "\n";
echo ctype_digit("0") ? "y" : "n", "\n";

echo ctype_xdigit("0123456789") ? "y" : "n", "\n";
echo ctype_xdigit("abcdef") ? "y" : "n", "\n";
echo ctype_xdigit("ABCDEF") ? "y" : "n", "\n";
echo ctype_xdigit("AbCdEf") ? "y" : "n", "\n";
echo ctype_xdigit("g") ? "y" : "n", "\n";
echo ctype_xdigit("0x10") ? "y" : "n", "\n";

echo ctype_space(" \t\n\r") ? "y" : "n", "\n";
echo ctype_space(" \t\nA") ? "y" : "n", "\n";
echo ctype_space("") ? "y" : "n", "\n";
echo ctype_space("\x0b") ? "y" : "n", "\n";
echo ctype_space("\x0c") ? "y" : "n", "\n";

echo ctype_punct("!@#") ? "y" : "n", "\n";
echo ctype_punct("!@#a") ? "y" : "n", "\n";
echo ctype_punct("") ? "y" : "n", "\n";
echo ctype_punct(",.") ? "y" : "n", "\n";
echo ctype_punct(" ") ? "y" : "n", "\n";

echo ctype_print("Hello!") ? "y" : "n", "\n";
echo ctype_print("Hello\t") ? "y" : "n", "\n";
echo ctype_print(" ") ? "y" : "n", "\n";
echo ctype_print("") ? "y" : "n", "\n";

echo ctype_cntrl("\t\n") ? "y" : "n", "\n";
echo ctype_cntrl("\t\nA") ? "y" : "n", "\n";
echo ctype_cntrl("") ? "y" : "n", "\n";
echo ctype_cntrl("\x00") ? "y" : "n", "\n";
echo ctype_cntrl("\x7f") ? "y" : "n", "\n";

echo ctype_graph("abc") ? "y" : "n", "\n";
echo ctype_graph("abc def") ? "y" : "n", "\n";
echo ctype_graph(" ") ? "y" : "n", "\n";
echo ctype_graph("") ? "y" : "n", "\n";

$mixed = "a";
echo ctype_alpha($mixed) ? "y" : "n", "\n";
echo ctype_lower($mixed) ? "y" : "n", "\n";
echo ctype_upper($mixed) ? "y" : "n", "\n";

$char = "1";
echo ctype_digit($char) ? "y" : "n", "\n";
echo ctype_alnum($char) ? "y" : "n", "\n";
echo ctype_alpha($char) ? "y" : "n", "\n";

$ctype_funcs = [
    "ctype_alpha", "ctype_alnum", "ctype_digit", "ctype_upper",
    "ctype_lower", "ctype_space", "ctype_punct", "ctype_print",
    "ctype_xdigit", "ctype_cntrl", "ctype_graph",
];
foreach ($ctype_funcs as $f) echo function_exists($f) ? "y" : "n", " ";
echo "\n";

echo ctype_alpha("hello world") ? "y" : "n", "\n";
echo ctype_alnum("hello world") ? "y" : "n", "\n";
echo ctype_space("hello world") ? "y" : "n", "\n";

$char_a = "a";
echo ctype_alpha($char_a) ? "y" : "n", "\n";

echo ctype_xdigit("00FFaa") ? "y" : "n", "\n";


echo ctype_alpha("abcdefghijklmnopqrstuvwxyz") ? "y" : "n", "\n";
echo ctype_alpha("ABCDEFGHIJKLMNOPQRSTUVWXYZ") ? "y" : "n", "\n";

echo ctype_print("Hello World!") ? "y" : "n", "\n";
echo ctype_punct(".,;:!?") ? "y" : "n", "\n";
