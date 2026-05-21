<?php
// regression: preg pattern modifiers are validated. an unknown modifier makes
// the whole call fail (false / null) instead of being silently ignored, and
// the D / J / n modifiers actually take effect.

// unknown modifier -> the call fails
var_dump(@preg_match('/abc/Z', 'abc'));        // false
var_dump(@preg_match('/abc/iZ', 'ABC'));       // false
var_dump(@preg_match_all('/x/Q', 'xxx'));      // false
var_dump(@preg_replace('/x/W', 'y', 'xxx'));   // null
var_dump(@preg_split('/,/G', 'a,b'));          // false

// the removed 'e' modifier is rejected too
var_dump(@preg_replace('/a/e', 'X', 'aaa'));   // null

// D (DOLLAR_ENDONLY): $ no longer matches before a trailing newline
var_dump(preg_match('/foo$/', "foo\n"));       // 1
var_dump(preg_match('/foo$/D', "foo\n"));      // 0

// n (NO_AUTO_CAPTURE): unnamed groups stop capturing
preg_match('/(abc)/n', 'abc', $m);
print_r($m);                                   // only [0] => abc

// J (DUPNAMES): duplicate named groups are allowed
var_dump(preg_match('/(?P<x>a)|(?P<x>b)/J', 'b', $m2));
echo $m2['x'], "\n";                           // b

// S (study) and X (extra) are accepted as no-ops
var_dump(preg_match('/abc/S', 'abc'));         // 1
var_dump(preg_match('/abc/X', 'abc'));         // 1

// known modifiers still work in combination
var_dump(preg_match('/^ABC$/im', "x\nabc\ny")); // 1
var_dump(preg_match('/a . b/x', 'a.b'));         // 1 (x ignores whitespace)

// leading whitespace before the delimiter is skipped (PHP does this), so an
// indented multi-line regex literal parses with its real delimiter/modifier
$indented = '
    /
        ^ \d+ $
    /x';
var_dump(preg_match($indented, '12345'));        // 1
var_dump(preg_match("  /abc/i", 'ABC'));         // 1
var_dump(preg_match("\n\t#xyz#", 'xyz'));        // 1
echo preg_match_all('
    / \w+ /x', 'one two three', $mw), "\n";       // 3
