<?php
$tests = [
    "abc",
    "ABC",
    "123",
    "abc123",
    "Hello World",
    "hello!",
    "  ",
    "\t\n\r",
    "",
    "a",
    "0",
    " ",
    "abc\0",
    "abc def",
    "AaBb",
    "deadBEEF",
    "0xFF",
    "Hello, World!",
    ".,!?",
];
// non-ASCII / high-byte ctype tests are locale-dependent (architectural)

$fns = ["ctype_alnum", "ctype_alpha", "ctype_digit", "ctype_space", "ctype_upper", "ctype_lower", "ctype_punct", "ctype_print", "ctype_cntrl", "ctype_xdigit", "ctype_graph"];

foreach ($fns as $fn) {
    echo "$fn:";
    foreach ($tests as $t) {
        $r = @$fn($t);
        echo $r ? "1" : "0";
    }
    echo "\n";
}

// edge cases on individual functions
var_dump(ctype_digit("0"));
var_dump(ctype_digit("00"));
var_dump(ctype_digit("0.0")); // false (period)
var_dump(ctype_digit(""));     // false (empty)

var_dump(ctype_alnum("abc123"));
var_dump(ctype_alnum("abc 123")); // false (space)
var_dump(ctype_alnum(""));         // false

var_dump(ctype_xdigit("DEADBEEF"));
var_dump(ctype_xdigit("0123abcdefABCDEF"));
var_dump(ctype_xdigit("xyz"));
var_dump(ctype_xdigit("123g"));

var_dump(ctype_space("\t\n\r\v\f "));
var_dump(ctype_space("  abc  "));

var_dump(ctype_upper("HELLO"));
var_dump(ctype_upper("Hello"));
var_dump(ctype_lower("hello"));
var_dump(ctype_lower("hellO"));

var_dump(ctype_punct(".,!?"));
var_dump(ctype_punct("hello"));
var_dump(ctype_punct(""));

var_dump(ctype_print("hello\t"));  // false (tab is ctrl, not print)
var_dump(ctype_print("hello world"));
var_dump(ctype_print("\x01"));     // false

var_dump(ctype_cntrl("\t\n\r"));
var_dump(ctype_cntrl("hello"));
var_dump(ctype_cntrl(""));

// graph: printable except space
var_dump(ctype_graph("hello"));
var_dump(ctype_graph("hello world"));
var_dump(ctype_graph("Hello,World!"));
