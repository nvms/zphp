<?php
// utf8_decode reads characters as php_next_utf8_char does: an ill-formed
// sequence or a character past latin-1 becomes one question mark
error_reporting(E_ALL & ~E_DEPRECATED);
foreach (["A\xC3\xA9B", "\xE2\x82\xAC", "A\xC0\xAFB", "\xF0\x9F\x98\x80x", "\xE2\x82", "a\x80b\xFFc", "\xED\xA0\x80", "\xC2"] as $s) echo bin2hex(utf8_decode($s)), "\n";
