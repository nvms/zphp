<?php
// covers: preg_match, preg_match_all, preg_replace, preg_replace_callback,
// preg_split, named captures, backreferences, character classes, quantifiers,
// anchors, alternation, lookahead/lookbehind, modifiers (i, m, s)

// test 1: basic preg_match
echo "=== Test 1: Basic Match ===\n";
$result = preg_match('/^hello/i', 'Hello World', $matches);
echo "Match: $result\n";
echo "Found: " . $matches[0] . "\n";

// test 2: capture groups
echo "\n=== Test 2: Capture Groups ===\n";
preg_match('/(\d{4})-(\d{2})-(\d{2})/', 'Date: 2024-03-15 is today', $matches);
echo "Full: " . $matches[0] . "\n";
echo "Year: " . $matches[1] . "\n";
echo "Month: " . $matches[2] . "\n";
echo "Day: " . $matches[3] . "\n";

// test 3: named captures
echo "\n=== Test 3: Named Captures ===\n";
preg_match('/(?P<year>\d{4})-(?P<month>\d{2})-(?P<day>\d{2})/', '2024-03-15', $matches);
echo "Year: " . $matches['year'] . "\n";
echo "Month: " . $matches['month'] . "\n";
echo "Day: " . $matches['day'] . "\n";

// test 4: preg_match_all
echo "\n=== Test 4: Match All ===\n";
$count = preg_match_all('/\b[A-Z]\w+/', 'Alice met Bob at the Park on Sunday', $matches);
echo "Count: $count\n";
echo "Words: " . implode(', ', $matches[0]) . "\n";

// test 5: preg_replace
echo "\n=== Test 5: Replace ===\n";
$result = preg_replace('/\d+/', '#', 'abc123def456ghi');
echo "Digits replaced: $result\n";

$result = preg_replace('/(\w+)@(\w+)\.(\w+)/', '$1 at $2 dot $3', 'user@example.com');
echo "Email: $result\n";

// test 6: preg_replace_callback
echo "\n=== Test 6: Replace Callback ===\n";
$result = preg_replace_callback('/\b\w+\b/', function($m) {
    return ucfirst(strtolower($m[0]));
}, 'hello WORLD foo BAR');
echo "Title case: $result\n";

$result = preg_replace_callback('/\d+/', function($m) {
    return $m[0] * 2;
}, 'a1 b2 c3 d10');
echo "Doubled: $result\n";

// test 7: preg_split
echo "\n=== Test 7: Split ===\n";
$parts = preg_split('/[\s,;]+/', 'one, two;  three four,,five');
echo "Parts: " . implode('|', $parts) . "\n";

$parts = preg_split('/(\d+)/', 'abc123def456', -1, PREG_SPLIT_DELIM_CAPTURE);
echo "With delims: " . implode('|', $parts) . "\n";

// test 8: character classes and quantifiers
echo "\n=== Test 8: Character Classes ===\n";
$tests = [
    ['/^\d+$/', '12345', 'digits'],
    ['/^[a-zA-Z]+$/', 'Hello', 'alpha'],
    ['/^\w+$/', 'hello_123', 'word'],
    ['/^\s+$/', '   ', 'whitespace'],
    ['/^[^aeiou]+$/i', 'brz', 'no vowels'],
];
foreach ($tests as $test) {
    $match = preg_match($test[0], $test[1]) ? 'yes' : 'no';
    echo $test[2] . ": " . $match . "\n";
}

// test 9: anchors and boundaries
echo "\n=== Test 9: Anchors ===\n";
echo "Start: " . (preg_match('/^hello/', 'hello world') ? 'yes' : 'no') . "\n";
echo "End: " . (preg_match('/world$/', 'hello world') ? 'yes' : 'no') . "\n";
echo "Word boundary: " . (preg_match('/\bcat\b/', 'the cat sat') ? 'yes' : 'no') . "\n";
echo "No boundary: " . (preg_match('/\bcat\b/', 'concatenate') ? 'yes' : 'no') . "\n";

// test 10: alternation
echo "\n=== Test 10: Alternation ===\n";
preg_match('/^(cat|dog|bird)$/', 'dog', $m);
echo "Animal: " . $m[1] . "\n";
echo "No match: " . (preg_match('/^(cat|dog|bird)$/', 'fish') ? 'yes' : 'no') . "\n";

// test 11: modifiers
echo "\n=== Test 11: Modifiers ===\n";
echo "Case insensitive: " . (preg_match('/hello/i', 'HELLO') ? 'yes' : 'no') . "\n";
echo "Multiline: " . (preg_match('/^world/m', "hello\nworld") ? 'yes' : 'no') . "\n";
echo "Dotall: " . (preg_match('/hello.world/s', "hello\nworld") ? 'yes' : 'no') . "\n";

// test 12: practical patterns
echo "\n=== Test 12: Practical Patterns ===\n";
$ipPattern = '/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/';
echo "Valid IP: " . (preg_match($ipPattern, '192.168.1.1') ? 'yes' : 'no') . "\n";
echo "Invalid IP: " . (preg_match($ipPattern, '256.1.1') ? 'yes' : 'no') . "\n";

$urlPattern = '/^https?:\/\/[\w.-]+(?:\/[\w.-]*)*\/?$/';
echo "Valid URL: " . (preg_match($urlPattern, 'https://example.com/path') ? 'yes' : 'no') . "\n";

// test 13: replace with limit
echo "\n=== Test 13: Replace with Limit ===\n";
$result = preg_replace('/\d/', 'X', 'a1b2c3d4', 2);
echo "Limited: $result\n";

// test 14: complex pattern - parse log line
echo "\n=== Test 14: Log Parser ===\n";
$log = '[2024-03-15 14:30:45] ERROR: Connection timeout (host=db.example.com, port=5432)';
preg_match('/\[(.+?)\] (\w+): (.+?) \((.+)\)/', $log, $m);
echo "Time: " . $m[1] . "\n";
echo "Level: " . $m[2] . "\n";
echo "Message: " . $m[3] . "\n";
echo "Details: " . $m[4] . "\n";

echo "\nAll regex tests passed!\n";
