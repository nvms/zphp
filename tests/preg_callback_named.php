<?php
// preg_replace_callback with named groups
echo preg_replace_callback('/(?<n>\d+)/', fn($m) => '['.$m['n'].']', 'a1 b22 c'), "\n";
echo preg_replace_callback('/(?<key>\w+)=(?<val>\d+)/', fn($m) => $m['key'].':'.$m['val'], 'x=1 y=2'), "\n";

// numeric still works
echo preg_replace_callback('/\d+/', fn($m) => '<'.$m[0].'>', 'a1 b22'), "\n";

// nested named
echo preg_replace_callback('/(?<outer>(?<inner>\w)\1)/', fn($m) => $m['inner'].'-'.$m['outer'], "aa bb cc"), "\n";

// with mixed access
echo preg_replace_callback('/(?<word>\w+)/', fn($m) => $m[0]==='b'?'B':$m['word'], "a b c"), "\n";

// preg_replace_callback_array
echo preg_replace_callback_array([
    '/\d/' => fn($m) => '['.$m[0].']',
    '/[a-z]/' => fn($m) => strtoupper($m[0]),
], "abc123"), "\n";

// non-capture remains unchanged
echo preg_replace_callback('/(?:\d+)/', fn($m) => '['.$m[0].']', 'x1 y2'), "\n";

// returning non-string
echo preg_replace_callback('/\d+/', fn($m) => intval($m[0]) * 10, "a1 b22 c"), "\n";

// preg_match_all returns named entries
preg_match_all('/(?<word>\w+):(?<num>\d+)/', "a:1 b:22", $m);
print_r($m);

// password_get_info options matches
$h = password_hash('x', PASSWORD_BCRYPT, ['cost' => 10]);
$info = password_get_info($h);
echo isset($info['options']['cost']) ? "has-cost\n" : "no-cost\n";
echo $info['options']['cost'] ?? '?', "\n";

// password_needs_rehash with cost
var_dump(password_needs_rehash($h, PASSWORD_BCRYPT, ['cost' => 10]));
var_dump(password_needs_rehash($h, PASSWORD_BCRYPT, ['cost' => 12]));
