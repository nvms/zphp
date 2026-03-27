<?php
// covers: fgetcsv, fputcsv, array_intersect_key, array_diff_assoc,
//   array_combine, array_column, array_map, array_filter, implode,
//   fopen, fclose, fwrite, rewind, str_putcsv (via fputcsv to memory),
//   array_keys, array_values, in_array, count, sprintf, usort

$csvData = "name,age,city,role\n" .
    "Alice,30,Portland,engineer\n" .
    "Bob,25,Seattle,designer\n" .
    "Charlie,35,Portland,engineer\n" .
    "Diana,28,Seattle,manager\n" .
    "Eve,32,Portland,designer\n";

$tmpFile = tempnam(sys_get_temp_dir(), 'csv_');
file_put_contents($tmpFile, $csvData);

// parse CSV with fgetcsv
$handle = fopen($tmpFile, 'r');
$headers = fgetcsv($handle, 0, ',', '"', '');
$rows = [];
while (($row = fgetcsv($handle, 0, ',', '"', '')) !== false) {
    $rows[] = array_combine($headers, $row);
}
fclose($handle);

echo "=== parsed " . count($rows) . " rows ===\n";
foreach ($rows as $row) {
    echo sprintf("  %s (age %s) - %s in %s\n", $row['name'], $row['age'], $row['role'], $row['city']);
}

// filter: only engineers
$engineers = array_filter($rows, function ($row) {
    return $row['role'] === 'engineer';
});
echo "\n=== engineers ===\n";
foreach ($engineers as $row) {
    echo "  " . $row['name'] . "\n";
}

// array_column: extract just names
$names = array_column($rows, 'name');
echo "\n=== all names ===\n";
echo "  " . implode(', ', $names) . "\n";

// array_column with index
$byName = array_column($rows, null, 'name');
echo "\n=== lookup by name ===\n";
echo "  Alice's city: " . $byName['Alice']['city'] . "\n";
echo "  Diana's role: " . $byName['Diana']['role'] . "\n";

// array_intersect_key: pick specific fields
$allowedKeys = array_flip(['name', 'city']);
echo "\n=== intersect_key (name+city only) ===\n";
foreach ($rows as $row) {
    $filtered = array_intersect_key($row, $allowedKeys);
    echo "  " . implode(', ', $filtered) . "\n";
}

// array_diff_assoc: find rows that differ from a reference
$reference = ['age' => '30', 'city' => 'Portland', 'role' => 'engineer'];
echo "\n=== diff_assoc vs reference ===\n";
foreach ($rows as $row) {
    $subset = ['age' => $row['age'], 'city' => $row['city'], 'role' => $row['role']];
    $diff = array_diff_assoc($subset, $reference);
    if (count($diff) > 0) {
        echo "  " . $row['name'] . " differs: " . implode(', ', array_map(
            function ($k, $v) { return "$k=$v"; },
            array_keys($diff),
            array_values($diff)
        )) . "\n";
    } else {
        echo "  " . $row['name'] . " matches reference\n";
    }
}

// write filtered CSV with fputcsv
$outFile = tempnam(sys_get_temp_dir(), 'csv_out_');
$out = fopen($outFile, 'w');
fputcsv($out, ['name', 'city'], ',', '"', '');
foreach ($rows as $row) {
    fputcsv($out, [$row['name'], $row['city']], ',', '"', '');
}
fclose($out);

$written = file_get_contents($outFile);
echo "\n=== written csv ===\n";
echo $written;

// sort by age descending
usort($rows, function ($a, $b) {
    return (int)$b['age'] - (int)$a['age'];
});
echo "=== sorted by age desc ===\n";
foreach ($rows as $row) {
    echo "  " . $row['name'] . ": " . $row['age'] . "\n";
}

// cleanup
unlink($tmpFile);
unlink($outFile);
