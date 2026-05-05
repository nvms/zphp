<?php
// covers: str_getcsv, fgetcsv, fputcsv, fopen (php://memory, php://temp),
//   fwrite, rewind, fclose, stream_get_contents, count, implode, explode,
//   array_map, str_replace, substr, strlen, ord, sprintf, var_export

function dump_row(array $row): string {
    $parts = [];
    foreach ($row as $f) {
        $parts[] = '[' . str_replace(["\r", "\n"], ['\\r', '\\n'], (string)$f) . ']';
    }
    return implode(' ', $parts);
}

echo "=== str_getcsv basics ===\n";
$cases = [
    'a,b,c',
    '"a","b","c"',
    'a,"b,c",d',                  // comma inside quoted
    '"a""b",c',                   // escaped quote
    'a,,c',                       // empty middle field
    ',a,',                        // empty edge fields
    '"line1\nline2",second',      // literal backslash-n (not real newline)
    "\"line1\nline2\",second",    // real embedded newline
    '"with ""nested"" quotes",ok',
    'unquoted "stray" middle',     // quote not at start - PHP keeps literally
    '"trailing space"  ,b',        // trailing whitespace after close quote
    "\xef\xbb\xbfa,b,c",           // UTF-8 BOM at start
    '',                            // empty input
    'one',                         // single field, no delim
];
foreach ($cases as $i => $c) {
    $row = str_getcsv($c, ',', '"', '\\');
    echo sprintf("  case %2d: %d field(s)\n", $i, count($row));
    echo "    in:  " . str_replace(["\r", "\n"], ['\\r', '\\n'], $c) . "\n";
    echo "    out: " . dump_row($row) . "\n";
}

echo "\n=== custom delimiters and enclosures ===\n";
echo "  tab: " . dump_row(str_getcsv("a\tb\tc", "\t", '"', '\\')) . "\n";
echo "  pipe: " . dump_row(str_getcsv('a|b|c', '|', '"', '\\')) . "\n";
echo "  semicolon: " . dump_row(str_getcsv('a;"b;c";d', ';', '"', '\\')) . "\n";
echo "  single-quote enclosure: " . dump_row(str_getcsv("a,'b,c',d", ',', "'", '\\')) . "\n";

echo "\n=== fgetcsv from memory stream ===\n";
$src = "name,age,note\n"
     . "\"Smith, Jane\",30,\"loves\nnewlines\"\n"
     . "\"O'Brien\",45,\"has \"\"quotes\"\" in note\"\n"
     . "Plain,99,simple\n";
$h = fopen('php://memory', 'r+');
fwrite($h, $src);
rewind($h);
$idx = 0;
while (($row = fgetcsv($h, 0, ',', '"', '')) !== false) {
    echo sprintf("  row %d (%d fields): %s\n", $idx++, count($row), dump_row($row));
}
fclose($h);

echo "\n=== roundtrip via fputcsv ===\n";
$rows = [
    ['name', 'description', 'qty'],
    ['Widget A', "first line\nsecond line", 10],
    ['Widget "Premium"', 'has, comma', 25],
    ["O'Reilly", 'apostrophe', 7],
    ['', 'empty name', 0],
    ['Trailing space ', ' leading space', 1],
];
$out = fopen('php://temp', 'w+');
foreach ($rows as $r) fputcsv($out, $r, ',', '"', '');
rewind($out);
$blob = stream_get_contents($out);
fclose($out);
echo "  serialized bytes: " . strlen($blob) . "\n";
echo "  begins with: " . substr($blob, 0, 30) . "...\n";

// parse it back
$h = fopen('php://memory', 'r+');
fwrite($h, $blob);
rewind($h);
$parsed = [];
while (($row = fgetcsv($h, 0, ',', '"', '')) !== false) $parsed[] = $row;
fclose($h);
echo "  parsed " . count($parsed) . " rows (sent " . count($rows) . ")\n";

$ok = count($parsed) === count($rows);
if ($ok) {
    foreach ($rows as $i => $r) {
        $expected = array_map('strval', $r);
        $got = array_map('strval', $parsed[$i]);
        if ($expected !== $got) {
            $ok = false;
            echo "  mismatch row $i:\n";
            echo "    sent: " . dump_row($expected) . "\n";
            echo "    got:  " . dump_row($got) . "\n";
        }
    }
}
echo "  roundtrip equal: " . ($ok ? 'yes' : 'no') . "\n";

echo "\n=== empty and pathological ===\n";
echo "  empty string: " . dump_row(str_getcsv('', ',', '"', '\\')) . "\n";
echo "  just delim: " . dump_row(str_getcsv(',', ',', '"', '\\')) . "\n";
echo "  just quote: " . dump_row(str_getcsv('"', ',', '"', '\\')) . "\n";
echo "  unterminated quote: " . dump_row(str_getcsv('"unterminated', ',', '"', '\\')) . "\n";
echo "  only commas: " . dump_row(str_getcsv(',,,', ',', '"', '\\')) . "\n";
echo "  whitespace only: " . dump_row(str_getcsv('   ', ',', '"', '\\')) . "\n";

echo "\n=== large field roundtrip ===\n";
$big = str_repeat('x', 5000) . ',with,"comma in quotes, here",and end';
$row = str_getcsv($big, ',', '"', '\\');
echo "  fields: " . count($row) . "\n";
echo "  field0 len: " . strlen($row[0]) . "\n";
echo "  field2: [" . $row[2] . "]\n";

echo "\n=== sprintf vs csv roundtrip stability ===\n";
$values = ["plain", "a,b", "a\"b", "a\nb", "  spaced  ", ""];
$out = fopen('php://temp', 'w+');
fputcsv($out, $values, ',', '"', '');
rewind($out);
$line = fgets($out);
fclose($out);
echo "  serialized line: " . str_replace(["\r", "\n"], ['\\r', '\\n'], $line) . "\n";
$back = str_getcsv(rtrim($line, "\r\n"), ',', '"', '\\');
echo "  fields back: " . count($back) . "\n";
foreach ($back as $i => $b) {
    echo sprintf("    %d: [%s] orig=[%s] match=%s\n", $i,
        str_replace(["\r", "\n"], ['\\r', '\\n'], $b),
        str_replace(["\r", "\n"], ['\\r', '\\n'], $values[$i]),
        $b === $values[$i] ? 'yes' : 'no');
}
