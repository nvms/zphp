<?php
// covers: fputcsv / fgetcsv round-trips, escape character behavior,
//   custom delimiters/enclosures, SplFileObject CSV iteration,
//   embedded quotes and newlines, BOM handling

$tmp = tempnam(sys_get_temp_dir(), 'csv');

echo "=== fputcsv writes valid CSV ===\n";
$rows = [
    ['id', 'name', 'email', 'notes'],
    [1, 'Alice', 'alice@example.com', 'normal'],
    [2, 'Bob "Smith"', 'bob@example.com', 'quoted in name'],
    [3, 'Carol', 'c@example.com', "has\nnewline"],
    [4, 'Dave, the second', 'dave@example.com', 'comma in name'],
    [5, '', 'empty@example.com', ''],
];

$f = fopen($tmp, 'w');
foreach ($rows as $r) fputcsv($f, $r, ',', '"', '');
fclose($f);

$content = file_get_contents($tmp);
echo "byte length > 0: " . (strlen($content) > 0 ? "yes" : "no") . "\n";
echo "starts with header: " . (str_starts_with($content, 'id,name') ? "yes" : "no") . "\n";

echo "\n=== fgetcsv round-trip ===\n";
$f = fopen($tmp, 'r');
$parsed = [];
while (($row = fgetcsv($f, 0, ',', '"', '')) !== false) $parsed[] = $row;
fclose($f);

echo "rows parsed: " . count($parsed) . "\n";
echo "header matches: " . ($parsed[0] === ['id', 'name', 'email', 'notes'] ? "yes" : "no") . "\n";
echo "embedded comma preserved: " . $parsed[4][1] . "\n";
echo "embedded newline preserved: " . str_replace("\n", '<LF>', $parsed[3][3]) . "\n";
echo "embedded quotes preserved: " . $parsed[2][1] . "\n";

echo "\n=== custom delimiter (TSV) ===\n";
$tsv = tempnam(sys_get_temp_dir(), 'tsv');
$f = fopen($tsv, 'w');
fputcsv($f, ['a', 'b\\c', 'd"e'], "\t", '"', '');
fputcsv($f, ['1', '2', '3'], "\t", '"', '');
fclose($f);

$f = fopen($tsv, 'r');
$first = fgetcsv($f, 0, "\t", '"', '');
$second = fgetcsv($f, 0, "\t", '"', '');
fclose($f);
echo "tab-separated col0: " . $first[0] . "\n";
echo "tab-separated col1: " . $first[1] . "\n";
echo "tab-separated col2: " . $first[2] . "\n";
echo "second row: " . implode(',', $second) . "\n";
unlink($tsv);

echo "\n=== SplFileObject CSV mode ===\n";
$spl = new SplFileObject($tmp);
$spl->setFlags(SplFileObject::READ_CSV | SplFileObject::SKIP_EMPTY | SplFileObject::DROP_NEW_LINE);
$count = 0;
foreach ($spl as $row) {
    if ($row === false || $row === [null]) continue;
    if ($count > 0) {
        echo sprintf("  id=%s name=%s\n", $row[0], $row[1]);
    }
    $count++;
}
echo "iter count: $count\n";

echo "\n=== str_getcsv direct parse ===\n";
$line = '1,"hello, world","embedded ""quotes"" here",plain';
$parsed_line = str_getcsv($line, ',', '"', '');
foreach ($parsed_line as $i => $field) echo "  [$i] '$field'\n";

echo "\n=== UTF-8 with BOM ===\n";
$bom = "\xEF\xBB\xBF";
$utf_path = tempnam(sys_get_temp_dir(), 'utf');
file_put_contents($utf_path, $bom . "name,city\nAlice,Paris\nBob,Tokyo\n");
$f = fopen($utf_path, 'r');
$header_raw = fgets($f);
fclose($f);
// BOM is preserved in first byte
echo "bom present: " . (str_starts_with($header_raw, $bom) ? "yes" : "no") . "\n";
echo "after BOM strip: " . str_replace($bom, '', $header_raw);
unlink($utf_path);

unlink($tmp);
echo "\ndone\n";
