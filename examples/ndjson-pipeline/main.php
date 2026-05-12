<?php
// covers: newline-delimited JSON streaming with generators,
//   incremental encode/decode, fopen + fread + fgets, JSON_THROW_ON_ERROR,
//   transform pipelines (filter, map, group)

$tmp = tempnam(sys_get_temp_dir(), 'ndjson');

echo "=== write NDJSON stream ===\n";
$f = fopen($tmp, 'w');
$events = [
    ['ts' => 1700000000, 'level' => 'info',  'msg' => 'startup'],
    ['ts' => 1700000005, 'level' => 'debug', 'msg' => 'connect',  'host' => 'db01'],
    ['ts' => 1700000010, 'level' => 'warn',  'msg' => 'slow query', 'ms' => 1234],
    ['ts' => 1700000020, 'level' => 'error', 'msg' => 'failure', 'code' => 500],
    ['ts' => 1700000030, 'level' => 'info',  'msg' => 'recovered'],
    ['ts' => 1700000035, 'level' => 'debug', 'msg' => 'connect',  'host' => 'db02'],
];
foreach ($events as $e) {
    fwrite($f, json_encode($e, JSON_UNESCAPED_SLASHES) . "\n");
}
fclose($f);
echo "file bytes: " . filesize($tmp) . "\n";

echo "\n=== iterate via generator ===\n";
function ndjson_iter(string $path): Generator {
    $f = fopen($path, 'r');
    while (!feof($f)) {
        $line = fgets($f);
        if ($line === false) break;
        $line = trim($line);
        if ($line === '') continue;
        yield json_decode($line, true, 512, JSON_THROW_ON_ERROR);
    }
    fclose($f);
}

$count = 0;
foreach (ndjson_iter($tmp) as $rec) $count++;
echo "events streamed: $count\n";

echo "\n=== filter by level ===\n";
$errors = [];
foreach (ndjson_iter($tmp) as $rec) {
    if ($rec['level'] === 'error') $errors[] = $rec;
}
echo "errors found: " . count($errors) . "\n";
echo "first error: " . $errors[0]['msg'] . " (code " . $errors[0]['code'] . ")\n";

echo "\n=== group counts ===\n";
$counts = [];
foreach (ndjson_iter($tmp) as $rec) {
    $counts[$rec['level']] = ($counts[$rec['level']] ?? 0) + 1;
}
ksort($counts);
foreach ($counts as $level => $n) echo "  $level: $n\n";

echo "\n=== aggregate by host ===\n";
$by_host = [];
foreach (ndjson_iter($tmp) as $rec) {
    if (isset($rec['host'])) $by_host[$rec['host']] = ($by_host[$rec['host']] ?? 0) + 1;
}
ksort($by_host);
foreach ($by_host as $h => $n) echo "  $h: $n\n";

echo "\n=== invalid line surfaces JsonException ===\n";
$bad = tempnam(sys_get_temp_dir(), 'ndjson_bad');
file_put_contents($bad, "{\"ok\":1}\nthis is not json\n{\"ok\":2}\n");
$err = null;
try {
    foreach (ndjson_iter($bad) as $rec) {}
} catch (JsonException $e) {
    $err = $e->getMessage();
}
echo "caught: " . ($err !== null ? "yes" : "no") . "\n";
unlink($bad);

echo "\n=== transform pipeline: ms histogram ===\n";
function bucket(int $ms): string {
    if ($ms < 100) return "< 100ms";
    if ($ms < 500) return "< 500ms";
    if ($ms < 2000) return "< 2s";
    return ">= 2s";
}
$buckets = [];
foreach (ndjson_iter($tmp) as $rec) {
    if (!isset($rec['ms'])) continue;
    $b = bucket($rec['ms']);
    $buckets[$b] = ($buckets[$b] ?? 0) + 1;
}
foreach ($buckets as $b => $n) echo "  $b: $n\n";

echo "\n=== rewrite as flat csv ===\n";
$csv_path = tempnam(sys_get_temp_dir(), 'ndcsv');
$out = fopen($csv_path, 'w');
fputcsv($out, ['ts', 'level', 'msg'], ',', '"', '');
foreach (ndjson_iter($tmp) as $rec) {
    fputcsv($out, [$rec['ts'], $rec['level'], $rec['msg']], ',', '"', '');
}
fclose($out);
$csv_bytes = file_get_contents($csv_path);
$lines = array_filter(explode("\n", $csv_bytes), fn($l) => $l !== '');
echo "csv rows (incl header): " . count($lines) . "\n";
echo "first data row: " . $lines[1] . "\n";
unlink($csv_path);

unlink($tmp);
echo "\ndone\n";
