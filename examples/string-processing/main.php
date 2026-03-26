<?php
// covers: str_replace, str_ireplace, substr, substr_count, substr_replace,
//   explode, implode, str_split, str_pad, str_repeat, str_word_count,
//   strpos, stripos, strrpos, strripos, strstr, strrev, ucwords,
//   addslashes, stripslashes, htmlspecialchars, strip_tags, wordwrap,
//   base64_encode, base64_decode, urlencode, urldecode, str_getcsv,
//   preg_match, preg_match_all, preg_replace, preg_replace_callback,
//   preg_split, sprintf, number_format, first-class callable, (int) cast

// --- text normalization pipeline ---

echo "=== Text Normalization ===\n";

$raw = "  Hello,   World!  This   is   a   TEST.  ";
$step1 = trim($raw);
$step2 = preg_replace('/\s+/', ' ', $step1);
$step3 = strtolower($step2);
echo "raw: '$raw'\n";
echo "normalized: '$step3'\n";

echo "word count: " . str_word_count($step3) . "\n";
$words = str_word_count($step3, 1);
echo "words: " . implode(', ', $words) . "\n";

// --- CSV parsing ---

echo "\n=== CSV Processing ===\n";

$csv_line = 'John,"Smith, Jr.",42,"New York"';
$fields = str_getcsv($csv_line, ',', '"', '');
echo "fields: " . count($fields) . "\n";
echo "rebuilt: " . implode(' | ', $fields) . "\n";

$tsv = "one\ttwo\tthree";
$tsv_fields = str_getcsv($tsv, "\t", '"', '');
echo "tsv: " . implode(', ', $tsv_fields) . "\n";

// --- slug generation ---

echo "\n=== Slug Generation ===\n";

function slugify($text) {
    $text = strtolower(trim($text));
    $text = preg_replace('/[^a-z0-9\s-]/', '', $text);
    $text = preg_replace('/[\s-]+/', '-', $text);
    $text = trim($text, '-');
    return $text;
}

$titles = [
    "Hello World!",
    "PHP 8.4 - What's New?",
    "  Spaces   Everywhere  ",
    "Special @#\$% Characters!!!",
];

foreach ($titles as $title) {
    echo "'$title' -> '" . slugify($title) . "'\n";
}

// --- template variable replacement ---

echo "\n=== Template Replacement ===\n";

$template = "Dear {{name}}, your order #{{order_id}} for {{item}} has shipped!";
$vars = [
    '{{name}}' => 'Alice',
    '{{order_id}}' => '12345',
    '{{item}}' => 'Widget Pro',
];

$result = str_replace(array_keys($vars), array_values($vars), $template);
echo "$result\n";

$count = substr_count($template, '{{');
echo "placeholders found: $count\n";

// --- string searching and extraction ---

echo "\n=== Search and Extract ===\n";

$haystack = "The quick brown fox jumps over the lazy dog. The fox is clever.";

echo "first 'fox': " . strpos($haystack, 'fox') . "\n";
echo "last 'fox': " . strrpos($haystack, 'fox') . "\n";
echo "case-insensitive 'THE': " . stripos($haystack, 'THE') . "\n";
echo "last case-insensitive 'THE': " . strripos($haystack, 'THE') . "\n";

$after_fox = strstr($haystack, 'fox');
echo "from first fox: $after_fox\n";

// --- encoding/decoding ---

echo "\n=== Encoding ===\n";

$html = '<div class="test">Hello & "World"</div>';
$encoded = htmlspecialchars($html);
echo "html encoded: $encoded\n";

$stripped = strip_tags($html);
echo "stripped: $stripped\n";

$data = "Hello, World! Special chars: @#\$%^&*()";
$b64 = base64_encode($data);
echo "base64: $b64\n";
echo "decoded matches: " . (base64_decode($b64) === $data ? 'yes' : 'no') . "\n";

$url_data = "hello world&foo=bar";
$url_enc = urlencode($url_data);
echo "url encoded: $url_enc\n";
echo "url decoded matches: " . (urldecode($url_enc) === $url_data ? 'yes' : 'no') . "\n";

// --- regex extraction ---

echo "\n=== Regex Extraction ===\n";

$log = "[2024-06-15 14:30:00] ERROR: Connection timeout (host=db.local, port=5432)";

preg_match('/\[(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})\] (\w+):/', $log, $matches);
echo "date: " . $matches[1] . "\n";
echo "time: " . $matches[2] . "\n";
echo "level: " . $matches[3] . "\n";

preg_match('/host=(\S+),/', $log, $m);
echo "host: " . $m[1] . "\n";

preg_match('/port=(\d+)/', $log, $m);
echo "port: " . $m[1] . "\n";

// --- multiple regex matches ---

echo "\n=== Multi-Match ===\n";

$text = "Contact us at support@example.com or sales@test.org. Old: admin@old.net";
preg_match_all('/[\w.+-]+@[\w.-]+\.\w+/', $text, $emails);
echo "emails found: " . count($emails[0]) . "\n";
foreach ($emails[0] as $email) {
    echo "  $email\n";
}

// --- regex replace with callback ---

echo "\n=== Callback Replace ===\n";

$text = "prices: $10, $25, $100, $7";
$result = preg_replace_callback('/\$(\d+)/', function($m) {
    $price = (int)$m[1];
    return '$' . number_format($price * 1.1, 2);
}, $text);
echo "$result\n";

// --- string padding and formatting ---

echo "\n=== Formatting ===\n";

$items = [
    ['Widget', 29.99, 3],
    ['Gadget Pro', 149.50, 1],
    ['Cable', 4.99, 10],
];

echo str_pad('Item', 15) . str_pad('Price', 10) . str_pad('Qty', 5) . "Total\n";
echo str_repeat('-', 40) . "\n";

$grand = 0;
foreach ($items as $item) {
    $total = $item[1] * $item[2];
    $grand += $total;
    echo str_pad($item[0], 15)
       . str_pad('$' . number_format($item[1], 2), 10)
       . str_pad((string)$item[2], 5)
       . '$' . number_format($total, 2) . "\n";
}
echo str_repeat('-', 40) . "\n";
echo str_pad('Grand Total', 30) . '$' . number_format($grand, 2) . "\n";

// --- string splitting and joining ---

echo "\n=== Split/Join ===\n";

$path = "/usr/local/bin/php";
$parts = explode('/', $path);
$parts = array_filter($parts, function($p) { return $p !== ''; });
echo "path parts: " . implode(' -> ', $parts) . "\n";

$sentence = "one,,two,,,three,,,,four";
$cleaned = array_filter(explode(',', $sentence), function($s) { return $s !== ''; });
echo "cleaned: " . implode(', ', $cleaned) . "\n";

// --- str_split and chunk processing ---

echo "\n=== Chunk Processing ===\n";

$hex = "48656c6c6f20576f726c6421";
$pairs = str_split($hex, 2);
$chars = array_map(function($h) { return chr(intval($h, 16)); }, $pairs);
echo "hex decoded: " . implode('', $chars) . "\n";

// --- word manipulation ---

echo "\n=== Word Manipulation ===\n";

echo "ucwords: " . ucwords("hello world foo bar") . "\n";
echo "ucwords delim: " . ucwords("hello-world_foo bar", "-_ ") . "\n";
echo "strrev: " . strrev("Hello World") . "\n";

$wrapped = wordwrap("The quick brown fox jumps over the lazy dog and then runs away", 25, "\n", true);
echo "wrapped:\n$wrapped\n";

// --- substr_replace ---

echo "\n=== Substr Replace ===\n";

$str = "Hello World";
echo "replace middle: " . substr_replace($str, "Beautiful ", 6, 0) . "\n";
echo "replace end: " . substr_replace($str, "PHP", 6, 5) . "\n";
echo "truncate+append: " . substr_replace($str, "...", 5) . "\n";

// --- sprintf formatting ---

echo "\n=== Sprintf ===\n";

echo sprintf("Name: %-15s Age: %3d", "Alice", 30) . "\n";
echo sprintf("Name: %-15s Age: %3d", "Bob", 7) . "\n";
echo sprintf("Hex: %x, Oct: %o, Bin: %b", 255, 255, 255) . "\n";
echo sprintf("Float: %.4f, Sci: %e", 3.14159, 0.00123) . "\n";
echo sprintf("Padded: %05d", 42) . "\n";

// --- addslashes/stripslashes ---

echo "\n=== Escape/Unescape ===\n";

$dangerous = "It's a \"test\" with \\backslash";
$escaped = addslashes($dangerous);
echo "escaped: $escaped\n";
echo "unescaped: " . stripslashes($escaped) . "\n";
echo "roundtrip: " . (stripslashes(addslashes($dangerous)) === $dangerous ? 'yes' : 'no') . "\n";

// --- preg_split ---

echo "\n=== Preg Split ===\n";

$expr = "3+14-5*2/7";
$tokens = preg_split('/([+\-*\/])/', $expr, -1, PREG_SPLIT_DELIM_CAPTURE | PREG_SPLIT_NO_EMPTY);
echo "tokens: " . implode(' ', $tokens) . "\n";

$csv_messy = "one  ,  two  ,  three  ,  four";
$clean = preg_split('/\s*,\s*/', $csv_messy);
echo "cleaned csv: " . implode('|', $clean) . "\n";

// --- case-insensitive replace ---

echo "\n=== Case-Insensitive Replace ===\n";

$text = "The CAT sat on the Cat mat near another cat";
$result = str_ireplace('cat', 'dog', $text);
echo "$result\n";

// --- first-class callable ---

echo "\n=== First-Class Callable ===\n";

$upper = strtoupper(...);
echo $upper("hello") . "\n";

$trimmer = trim(...);
echo "'" . $trimmer("  spaced  ") . "'\n";

$lengths = array_map(strlen(...), ["hello", "world", "hi"]);
echo "lengths: " . implode(', ', $lengths) . "\n";

echo "\nDone.\n";
