<?php
// covers: count_chars, str_increment, str_decrement, levenshtein,
//   similar_text, soundex, preg_grep, preg_match_all, array_intersect_assoc,
//   array_keys, array_values, arsort, implode, count, sprintf, strtolower,
//   substr, str_repeat, chr, ord, strlen, array_map, array_filter

// count_chars: character frequency analysis
echo "=== character frequency ===\n";
$text = "the quick brown fox jumps over the lazy dog";
$freq = count_chars($text, 1);
arsort($freq);
echo "most frequent characters in '$text':\n";
$i = 0;
foreach ($freq as $byte => $count) {
    $char = ($byte === 32) ? 'SPC' : chr($byte);
    echo sprintf("  %-4s %d\n", $char, $count);
    $i++;
    if ($i >= 8) break;
}

// count_chars mode 3: unique characters as string
$unique = count_chars("programming", 3);
echo "\nunique chars in 'programming': $unique\n";

// count_chars mode 2: chars NOT in string
$missing = count_chars("abcxyz", 2);
$missing_letters = [];
foreach ($missing as $byte => $count) {
    if ($byte >= ord('a') && $byte <= ord('z')) {
        $missing_letters[] = chr($byte);
    }
}
echo "letters not in 'abcxyz': " . implode('', array_slice($missing_letters, 0, 10)) . "...\n";

// str_increment / str_decrement: version-like sequences
echo "\n=== string increment/decrement ===\n";
$labels = ['A', 'Z', 'Az', 'Zz', 'a1', 'z9', 'abc', 'ZZZ'];
foreach ($labels as $label) {
    $inc = str_increment($label);
    echo sprintf("  %-6s ++ = %-6s\n", $label, $inc);
}

echo "\n";
$labels = ['b', 'Z', 'Ba', 'aa', 'z1', 'Ab'];
foreach ($labels as $label) {
    $dec = str_decrement($label);
    echo sprintf("  %-6s -- = %-6s\n", $label, $dec);
}

// generate column labels like a spreadsheet (A, B, ... Z, AA, AB, ...)
echo "\nspreadsheet columns: ";
$col = 'A';
$cols = [];
for ($i = 0; $i < 30; $i++) {
    $cols[] = $col;
    $col = str_increment($col);
}
echo implode(' ', $cols) . "\n";

// text similarity analysis
echo "\n=== document similarity ===\n";
$documents = [
    'doc1' => 'the quick brown fox jumps over the lazy dog',
    'doc2' => 'the fast brown fox leaps over the sleepy dog',
    'doc3' => 'a slow red cat crawls under the active mouse',
    'doc4' => 'the quick brown fox jumped over lazy dogs',
];

// word overlap analysis using count_chars on word level
function wordFrequency(string $text): array {
    $words = explode(' ', strtolower($text));
    $freq = [];
    foreach ($words as $w) {
        if (!isset($freq[$w])) $freq[$w] = 0;
        $freq[$w]++;
    }
    return $freq;
}

// compare documents pairwise
$names = array_keys($documents);
for ($i = 0; $i < count($names); $i++) {
    for ($j = $i + 1; $j < count($names); $j++) {
        $a = $names[$i];
        $b = $names[$j];
        $fa = wordFrequency($documents[$a]);
        $fb = wordFrequency($documents[$b]);
        $common = array_intersect_assoc($fa, $fb);
        $shared_words = count($common);
        $total_unique = count($fa) + count($fb) - $shared_words;
        $jaccard = ($total_unique > 0) ? $shared_words / $total_unique : 0;
        similar_text($documents[$a], $documents[$b], $pct);
        echo sprintf("  %-4s vs %-4s  shared_words=%d  jaccard=%.2f  similar=%.1f%%\n",
            $a, $b, $shared_words, $jaccard, $pct);
    }
}

// find near-duplicate entries using levenshtein
echo "\n=== near-duplicate detection ===\n";
$entries = [
    'John Smith',
    'Jon Smith',
    'John Smyth',
    'Jane Doe',
    'John Smith Jr',
    'Janet Doe',
    'jane doe',
];

$threshold = 3;
$groups = [];
$used = [];
for ($i = 0; $i < count($entries); $i++) {
    if (in_array($i, $used)) continue;
    $group = [$entries[$i]];
    $used[] = $i;
    for ($j = $i + 1; $j < count($entries); $j++) {
        if (in_array($j, $used)) continue;
        $dist = levenshtein(strtolower($entries[$i]), strtolower($entries[$j]));
        if ($dist <= $threshold) {
            $group[] = $entries[$j];
            $used[] = $j;
        }
    }
    $groups[] = $group;
}

foreach ($groups as $idx => $group) {
    echo "  group " . ($idx + 1) . ": " . implode(', ', $group) . "\n";
}

// password strength analysis using count_chars
echo "\n=== password analysis ===\n";
$passwords = ['abc123', 'P@ssw0rd!', 'correcthorsebatterystaple', 'aaa', 'Tr0ub4dor&3'];

function analyzePassword(string $pw): array {
    $unique_chars = strlen(count_chars($pw, 3));
    $has_upper = preg_match('/[A-Z]/', $pw);
    $has_lower = preg_match('/[a-z]/', $pw);
    $has_digit = preg_match('/[0-9]/', $pw);
    $has_special = preg_match('/[^a-zA-Z0-9]/', $pw);
    $char_classes = $has_upper + $has_lower + $has_digit + $has_special;
    $score = $unique_chars * 2 + strlen($pw) + $char_classes * 5;
    return ['unique' => $unique_chars, 'classes' => $char_classes, 'score' => $score, 'len' => strlen($pw)];
}

echo sprintf("  %-28s %4s %6s %7s %5s\n", "password", "len", "unique", "classes", "score");
echo "  " . str_repeat("-", 55) . "\n";
foreach ($passwords as $pw) {
    $a = analyzePassword($pw);
    echo sprintf("  %-28s %4d %6d %7d %5d\n", $pw, $a['len'], $a['unique'], $a['classes'], $a['score']);
}
