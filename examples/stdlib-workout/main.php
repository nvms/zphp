<?php
// covers: sprintf, printf, number_format, str_pad, str_repeat, str_contains,
//   str_starts_with, str_ends_with, substr_replace, wordwrap, nl2br, chunk_split,
//   str_word_count, str_getcsv, strip_tags, html_entity_decode,
//   array_column, array_combine, array_unique, array_chunk, array_splice,
//   array_pad, array_product, array_sum, array_count_values, array_intersect,
//   array_diff_key, array_flip, array_fill, array_fill_keys, range,
//   array_replace, array_key_first, array_key_last,
//   preg_match_all, preg_replace_callback, preg_split, preg_match,
//   abs, ceil, floor, round, max, min, pow, sqrt, log, fmod, intdiv,
//   base_convert, bindec, decoct, hexdec, octdec,
//   intval, floatval, strval, settype, is_numeric, is_scalar,
//   compact, extract, usort, array_map, array_filter, array_reduce,
//   array_walk, ksort, arsort, array_rand, shuffle,
//   checkdate, date, time, strtotime, microtime

// --- string formatting ---

echo "=== String Formatting ===\n";

$name = "Alice";
$score = 95.678;
$rank = 3;

echo sprintf("Player: %s | Score: %.2f | Rank: #%d\n", $name, $score, $rank);
echo sprintf("Hex: %x | Oct: %o | Bin: %b\n", 255, 255, 255);
echo sprintf("Padded: [%10s] [%-10s] [%05d]\n", "right", "left", 42);
echo sprintf("Sign: %+d %+d\n", 42, -42);

echo sprintf("Price: $%s\n", number_format(1234567.891, 2, '.', ','));
echo sprintf("EU: %s\n", number_format(1234567.891, 2, ',', '.'));

echo str_pad("Title", 20, "=-", STR_PAD_BOTH) . "\n";
echo str_pad("42", 8, "0", STR_PAD_LEFT) . "\n";
echo str_repeat("ab", 4) . "\n";

// --- string inspection ---

echo "\n=== String Inspection ===\n";

$haystack = "The quick brown fox jumps over the lazy dog";

echo str_contains($haystack, "brown") ? "contains brown\n" : "no brown\n";
echo str_starts_with($haystack, "The") ? "starts with The\n" : "no\n";
echo str_ends_with($haystack, "dog") ? "ends with dog\n" : "no\n";
echo "word count: " . str_word_count($haystack) . "\n";

echo substr_replace("hello world", "PHP", 6, 5) . "\n";

$wrapped = wordwrap("The quick brown fox jumped over the lazy dog", 15, "\n", true);
echo $wrapped . "\n";

// --- string escaping ---

echo "\n=== String Escaping ===\n";

echo strip_tags("<p>Hello <b>World</b></p>") . "\n";
echo strip_tags("<p>Hello <b>World</b></p>", "<b>") . "\n";
echo html_entity_decode("&lt;div&gt;test&lt;/div&gt;") . "\n";

// --- csv parsing ---

echo "\n=== CSV Parsing ===\n";

$csv_lines = [
    "name,age,city",
    "Alice,30,New York",
    "Bob,25,London",
    "Charlie,35,Paris"
];

$headers = str_getcsv($csv_lines[0], ',', '"', '');
$rows = [];
for ($i = 1; $i < count($csv_lines); $i++) {
    $rows[] = array_combine($headers, str_getcsv($csv_lines[$i], ',', '"', ''));
}

$names = array_column($rows, 'name');
echo "Names: " . implode(', ', $names) . "\n";

$cities = array_column($rows, 'city', 'name');
echo "Alice lives in: " . $cities['Alice'] . "\n";

$ages = array_column($rows, 'age');
$avg_age = array_sum($ages) / count($ages);
echo sprintf("Average age: %.1f\n", $avg_age);

// --- array operations ---

echo "\n=== Array Operations ===\n";

$data = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];
echo "Unique: " . implode(', ', array_values(array_unique($data))) . "\n";

$counts = array_count_values($data);
ksort($counts);
echo "Counts: ";
foreach ($counts as $v => $c) {
    echo "$v=>$c ";
}
echo "\n";

$chunks = array_chunk($data, 4);
echo "Chunks: " . count($chunks) . " groups\n";
foreach ($chunks as $i => $chunk) {
    echo "  [$i]: " . implode(', ', $chunk) . "\n";
}

$nums = [1, 2, 3, 4, 5];
echo "Sum: " . array_sum($nums) . "\n";
echo "Product: " . array_product($nums) . "\n";

$padded = array_pad($nums, 8, 0);
echo "Padded: " . implode(', ', $padded) . "\n";
$padded_left = array_pad($nums, -8, 0);
echo "Padded left: " . implode(', ', $padded_left) . "\n";

$letters = range('a', 'e');
echo "Range: " . implode(', ', $letters) . "\n";

$stepped = range(0, 20, 5);
echo "Stepped: " . implode(', ', $stepped) . "\n";

$filled = array_fill(5, 3, "x");
echo "Fill: ";
print_r($filled);

$keys = ['a', 'b', 'c'];
$filled_keys = array_fill_keys($keys, 0);
echo "Fill keys: ";
print_r($filled_keys);

$flipped = array_flip(['a' => 1, 'b' => 2, 'c' => 3]);
echo "Flipped: ";
print_r($flipped);

// --- array set operations ---

echo "\n=== Array Set Operations ===\n";

$a = ['x' => 1, 'y' => 2, 'z' => 3];
$b = ['y' => 20, 'z' => 30, 'w' => 40];

$replaced = array_replace($a, $b);
echo "Replace: ";
print_r($replaced);

$common_vals = array_intersect([1, 2, 3, 4, 5], [3, 4, 5, 6, 7]);
echo "Intersect: " . implode(', ', $common_vals) . "\n";

$diff_keys = array_diff_key($a, $b);
echo "Diff key: ";
print_r($diff_keys);

// --- array splice ---

echo "\n=== Array Splice ===\n";

$arr = ['a', 'b', 'c', 'd', 'e'];
$removed = array_splice($arr, 1, 2, ['X', 'Y', 'Z']);
echo "After splice: " . implode(', ', $arr) . "\n";
echo "Removed: " . implode(', ', $removed) . "\n";

// --- sorting ---

echo "\n=== Sorting ===\n";

$items = [
    ['name' => 'Banana', 'price' => 1.50],
    ['name' => 'Apple', 'price' => 2.00],
    ['name' => 'Cherry', 'price' => 3.50],
    ['name' => 'Apple', 'price' => 1.75],
];

usort($items, function($a, $b) {
    $cmp = strcmp($a['name'], $b['name']);
    if ($cmp !== 0) return $cmp;
    return $a['price'] <=> $b['price'];
});

foreach ($items as $item) {
    echo sprintf("  %s: $%.2f\n", $item['name'], $item['price']);
}

// --- functional array ops ---

echo "\n=== Functional ===\n";

$numbers = range(1, 10);

$squares = array_map(fn($n) => $n * $n, $numbers);
echo "Squares: " . implode(', ', $squares) . "\n";

$evens = array_filter($numbers, fn($n) => $n % 2 === 0);
echo "Evens: " . implode(', ', $evens) . "\n";

$sum = array_reduce($numbers, fn($carry, $n) => $carry + $n, 0);
echo "Sum via reduce: $sum\n";

$walked = [];
array_walk($numbers, function($val, $key) use (&$walked) {
    $walked[] = "$key:$val";
});
echo "Walked: " . implode(', ', $walked) . "\n";

// --- compact/extract ---

echo "\n=== Compact/Extract ===\n";

$first = "John";
$last = "Doe";
$age = 30;
$person = compact('first', 'last', 'age');
echo sprintf("%s %s, age %d\n", $person['first'], $person['last'], $person['age']);

$record = ['color' => 'blue', 'size' => 'large', 'qty' => 5];
extract($record);
echo "$color $size $qty\n";

// --- regex ---

echo "\n=== Regex ===\n";

$text = "Call 555-1234 or 555-5678 or email alice@example.com";

preg_match_all('/\d{3}-\d{4}/', $text, $matches);
echo "Phones: " . implode(', ', $matches[0]) . "\n";

$result = preg_replace_callback('/\d{3}-(\d{4})/', function($m) {
    return "XXX-" . $m[1];
}, $text);
echo "Redacted: $result\n";

$parts = preg_split('/[\s,;]+/', "one, two; three four");
echo "Split: " . implode(' | ', $parts) . "\n";

// --- math ---

echo "\n=== Math ===\n";

echo "abs(-42): " . abs(-42) . "\n";
echo "ceil(4.3): " . ceil(4.3) . "\n";
echo "floor(4.7): " . floor(4.7) . "\n";
echo "round(4.567, 2): " . round(4.567, 2) . "\n";
echo "pow(2, 10): " . pow(2, 10) . "\n";
echo "sqrt(144): " . sqrt(144) . "\n";
echo "log(M_E): " . round(log(M_E), 10) . "\n";
echo "fmod(10, 3): " . fmod(10, 3) . "\n";
echo "intdiv(7, 2): " . intdiv(7, 2) . "\n";
echo "max(1,2,3): " . max(1, 2, 3) . "\n";
echo "min(1,2,3): " . min(1, 2, 3) . "\n";

echo "base_convert('ff', 16, 10): " . base_convert('ff', 16, 10) . "\n";
echo "hexdec('ff'): " . hexdec('ff') . "\n";
echo "decoct(255): " . decoct(255) . "\n";
echo "bindec('11111111'): " . bindec('11111111') . "\n";
echo "octdec('377'): " . octdec('377') . "\n";

// --- type juggling ---

echo "\n=== Type Juggling ===\n";

echo "intval('42abc'): " . intval('42abc') . "\n";
echo "intval('0xFF', 16): " . intval('0xFF', 16) . "\n";
echo "floatval('3.14xyz'): " . floatval('3.14xyz') . "\n";
echo "strval(42): " . strval(42) . "\n";
echo "is_numeric('42.5'): " . (is_numeric('42.5') ? 'true' : 'false') . "\n";
echo "is_numeric('0xFF'): " . (is_numeric('0xFF') ? 'true' : 'false') . "\n";
echo "is_scalar(42): " . (is_scalar(42) ? 'true' : 'false') . "\n";
echo "is_scalar([]): " . (is_scalar([]) ? 'true' : 'false') . "\n";

$var = "42";
settype($var, "integer");
echo "settype to int: " . $var . " (" . gettype($var) . ")\n";

// --- date/time ---

echo "\n=== Date/Time ===\n";

$ts = mktime(14, 30, 0, 6, 15, 2025);
echo "Date: " . date('Y-m-d H:i:s', $ts) . "\n";
echo "Day: " . date('l', $ts) . "\n";
echo "ISO: " . date('c', $ts) . "\n";

$next_year = strtotime('+1 year', $ts);
echo "Next year: " . date('Y-m-d', $next_year) . "\n";

echo "Range check: " . (checkdate(2, 29, 2024) ? "2024 is leap" : "not leap") . "\n";
echo "Range check: " . (checkdate(2, 29, 2023) ? "2023 is leap" : "not leap") . "\n";

// --- putting it together: report generator ---

echo "\n=== Report Generator ===\n";

$sales = [
    ['rep' => 'Alice', 'region' => 'North', 'amount' => 15000],
    ['rep' => 'Bob', 'region' => 'South', 'amount' => 22000],
    ['rep' => 'Alice', 'region' => 'North', 'amount' => 18000],
    ['rep' => 'Charlie', 'region' => 'East', 'amount' => 12000],
    ['rep' => 'Bob', 'region' => 'South', 'amount' => 9500],
    ['rep' => 'Diana', 'region' => 'West', 'amount' => 28000],
    ['rep' => 'Charlie', 'region' => 'East', 'amount' => 17500],
    ['rep' => 'Alice', 'region' => 'North', 'amount' => 21000],
];

$by_rep = [];
foreach ($sales as $sale) {
    $rep = $sale['rep'];
    if (!isset($by_rep[$rep])) {
        $by_rep[$rep] = ['sales' => [], 'total' => 0];
    }
    $by_rep[$rep]['sales'][] = $sale['amount'];
    $by_rep[$rep]['total'] += $sale['amount'];
}

ksort($by_rep);

$header = sprintf("%-10s %8s %8s %10s", "Rep", "Count", "Avg", "Total");
echo $header . "\n";
echo str_repeat("-", strlen($header)) . "\n";

foreach ($by_rep as $rep => $data) {
    $cnt = count($data['sales']);
    $avg = $data['total'] / $cnt;
    echo sprintf("%-10s %8d %8s %10s\n",
        $rep,
        $cnt,
        number_format($avg, 0, '.', ','),
        number_format($data['total'], 0, '.', ',')
    );
}

$grand_total = array_sum(array_column($sales, 'amount'));
echo str_repeat("-", strlen($header)) . "\n";
echo sprintf("%-10s %8d %8s %10s\n",
    "TOTAL",
    count($sales),
    number_format($grand_total / count($sales), 0, '.', ','),
    number_format($grand_total, 0, '.', ',')
);

// --- region breakdown with array ops ---

echo "\n=== Region Breakdown ===\n";

$regions = array_unique(array_column($sales, 'region'));
sort($regions);

foreach ($regions as $region) {
    $region_sales = array_filter($sales, fn($s) => $s['region'] === $region);
    $amounts = array_column($region_sales, 'amount');
    $total = array_sum($amounts);
    $reps = array_unique(array_column($region_sales, 'rep'));
    echo sprintf("  %s: %s (%s)\n",
        $region,
        number_format($total, 0, '.', ','),
        implode(', ', $reps)
    );
}

echo "\nDone.\n";
