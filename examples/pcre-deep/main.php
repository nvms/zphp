<?php
// covers: PCRE lookbehind/lookahead, named groups, unicode property, multibyte mode,
//   preg_replace_callback, preg_split flags, anchored matching, PREG_OFFSET_CAPTURE

echo "=== named groups ===\n";
$re = '/^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})$/';
if (preg_match($re, '2026-05-11', $m)) {
    echo "year={$m['year']} month={$m['month']} day={$m['day']}\n";
}

echo "\n=== lookahead and lookbehind ===\n";
$text = 'price: $100 USD plus $25 service fee';
preg_match_all('/(?<=\$)\d+(?= USD)/', $text, $m);
echo "dollar with USD: " . implode(',', $m[0]) . "\n";

preg_match_all('/(?<!\$)\b\d+\b/', $text, $m);
echo "numbers NOT preceded by $: " . implode(',', $m[0]) . "\n";

preg_match_all('/\d+(?=\s)/', 'a 1 b 22 c 333', $m);
echo "followed by space: " . implode(',', $m[0]) . "\n";

echo "\n=== unicode property ===\n";
$text = 'Hello, 世界! Café — naïve';
preg_match_all('/\p{L}+/u', $text, $m);
echo "letters: " . implode(' | ', $m[0]) . "\n";
preg_match_all('/\p{N}+/u', "amount 42 and 3.14 and 100%", $m);
echo "digits: " . implode(',', $m[0]) . "\n";

echo "\n=== preg_replace_callback ===\n";
$text = 'order #1234 and #5678 not #abc';
$out = preg_replace_callback('/#(\d+)/', fn($m) => sprintf('[order:%05d]', (int)$m[1]), $text);
echo "$out\n";

echo "\n=== preg_replace_callback_array ===\n";
$text = 'Hello World';
$out = preg_replace_callback_array([
    '/(?<=\w)\w/' => fn($m) => strtolower($m[0]),
    '/^\w/' => fn($m) => strtoupper($m[0]),
], $text);
echo "$out\n";

echo "\n=== preg_split with limit and flags ===\n";
$csv = "a,b,c,d,e,f";
$parts = preg_split('/,/', $csv, 3);
echo "limit 3: " . json_encode($parts) . "\n";

$with_empty = preg_split('/,/', ",a,,b,");
echo "default (keeps empty): " . json_encode($with_empty) . "\n";

$no_empty = preg_split('/,/', ",a,,b,", -1, PREG_SPLIT_NO_EMPTY);
echo "no-empty: " . json_encode($no_empty) . "\n";

$with_offsets = preg_split('/\s+/', 'hello   world  again', -1, PREG_SPLIT_OFFSET_CAPTURE);
foreach ($with_offsets as $o) echo "  '$o[0]' at $o[1]\n";

echo "\n=== anchored boundary ===\n";
preg_match_all('/\bcat\b/', 'cats, scat, cat, category, cat-dog', $m);
echo "matches: " . count($m[0]) . " ('" . implode("','", $m[0]) . "')\n";

echo "\n=== PREG_OFFSET_CAPTURE ===\n";
preg_match_all('/\d+/', 'tx-001 amount=42 ref=99', $m, PREG_OFFSET_CAPTURE);
foreach ($m[0] as $hit) echo "  '$hit[0]' @ $hit[1]\n";

echo "\n=== preg_quote ===\n";
$tricky = 'foo.bar(baz)?+*$';
echo "quoted: " . preg_quote($tricky) . "\n";
echo "match: " . (preg_match('/^' . preg_quote($tricky) . '$/', $tricky) ? "yes" : "no") . "\n";

echo "\n=== email-like extraction ===\n";
$text = 'send to alice@example.com or bob+work@corp.local or admin@127.0.0.1';
preg_match_all('/[\w+.-]+@[\w.-]+\.[a-z]{2,}/i', $text, $m);
foreach ($m[0] as $e) echo "  $e\n";

echo "\n=== conditional with backreferences ===\n";
$text = 'aa bb cc dd ee ff aa';
preg_match_all('/\b(\w)\1\b/', $text, $m);
echo "doubles: " . implode(',', $m[0]) . "\n";

echo "\n=== case-insensitive with multiline flag ===\n";
$multiline = "Line ONE\nline two\nLINE three";
preg_match_all('/^line .+/im', $multiline, $m);
echo "matched lines:\n" . implode("\n", $m[0]) . "\n";

echo "\n=== preg_grep filter array ===\n";
$lines = ['error: foo', 'info: bar', 'warn: baz', 'error: qux'];
$errors = preg_grep('/^error:/', $lines);
echo "errors: " . count($errors) . "\n";
foreach ($errors as $e) echo "  $e\n";

echo "\ndone\n";
