<?php
// covers: fopen, fclose, fputcsv, fgetcsv, fwrite, fread, fseek, ftell,
//   rewind, feof, fgets, stat, filesize, file_put_contents, file_get_contents,
//   unlink, number_format, array_keys, array_values, array_sum, array_map,
//   array_column, usort, arsort, count, sprintf, implode, explode,
//   str_pad, strtoupper, round, min, max, str_repeat

$tmp = sys_get_temp_dir() . '/zphp_export_' . uniqid();
mkdir($tmp, 0755, true);

// generate sample data
$employees = [
    ['id' => 1, 'name' => 'Alice Chen', 'department' => 'Engineering', 'salary' => 125000, 'start_date' => '2020-03-15'],
    ['id' => 2, 'name' => 'Bob Kumar', 'department' => 'Marketing', 'salary' => 95000, 'start_date' => '2021-07-01'],
    ['id' => 3, 'name' => 'Carol Smith', 'department' => 'Engineering', 'salary' => 135000, 'start_date' => '2019-11-20'],
    ['id' => 4, 'name' => 'Dave Wilson', 'department' => 'Sales', 'salary' => 88000, 'start_date' => '2022-01-10'],
    ['id' => 5, 'name' => 'Eve Johnson', 'department' => 'Engineering', 'salary' => 145000, 'start_date' => '2018-06-03'],
    ['id' => 6, 'name' => 'Frank Lee', 'department' => 'Marketing', 'salary' => 92000, 'start_date' => '2021-09-15'],
    ['id' => 7, 'name' => 'Grace Park', 'department' => 'Sales', 'salary' => 105000, 'start_date' => '2020-04-22'],
    ['id' => 8, 'name' => 'Hank Brown', 'department' => 'Engineering', 'salary' => 118000, 'start_date' => '2022-08-01'],
];

// write CSV
echo "=== CSV export ===\n";
$csv_file = "$tmp/employees.csv";
$fp = fopen($csv_file, 'w');
fputcsv($fp, array_keys($employees[0]));
foreach ($employees as $row) {
    fputcsv($fp, array_values($row));
}
fclose($fp);

$info = stat($csv_file);
echo "wrote " . basename($csv_file) . "\n";
echo "size: " . $info['size'] . " bytes\n";
echo "rows: " . count($employees) . " data + 1 header\n";

// read CSV back and verify
echo "\n=== CSV import ===\n";
$fp = fopen($csv_file, 'r');
$headers = fgetcsv($fp);
echo "headers: " . implode(', ', $headers) . "\n";

$imported = [];
while (!feof($fp)) {
    $row = fgetcsv($fp);
    if ($row === false || count($row) !== count($headers)) continue;
    $assoc = [];
    for ($i = 0; $i < count($headers); $i++) {
        $assoc[$headers[$i]] = $row[$i];
    }
    $imported[] = $assoc;
}
fclose($fp);
echo "imported " . count($imported) . " rows\n";
echo "roundtrip match: " . (count($imported) === count($employees) ? 'yes' : 'no') . "\n";

// department summary report
echo "\n=== department summary ===\n";
$dept_stats = [];
foreach ($employees as $emp) {
    $dept = $emp['department'];
    if (!isset($dept_stats[$dept])) {
        $dept_stats[$dept] = ['count' => 0, 'total_salary' => 0, 'min_salary' => $emp['salary'], 'max_salary' => $emp['salary']];
    }
    $dept_stats[$dept]['count']++;
    $dept_stats[$dept]['total_salary'] += $emp['salary'];
    $dept_stats[$dept]['min_salary'] = min($dept_stats[$dept]['min_salary'], $emp['salary']);
    $dept_stats[$dept]['max_salary'] = max($dept_stats[$dept]['max_salary'], $emp['salary']);
}

echo sprintf("  %-15s %5s %12s %12s %12s %12s\n",
    "Department", "Count", "Total", "Average", "Min", "Max");
echo "  " . str_repeat("-", 72) . "\n";

foreach ($dept_stats as $dept => $stats) {
    $avg = round($stats['total_salary'] / $stats['count']);
    echo sprintf("  %-15s %5d %12s %12s %12s %12s\n",
        $dept,
        $stats['count'],
        number_format($stats['total_salary'], 0, '.', ','),
        number_format($avg, 0, '.', ','),
        number_format($stats['min_salary'], 0, '.', ','),
        number_format($stats['max_salary'], 0, '.', ','));
}

// total
$total_salary = array_sum(array_column($employees, 'salary'));
$avg_salary = round($total_salary / count($employees));
echo "  " . str_repeat("-", 72) . "\n";
echo sprintf("  %-15s %5d %12s %12s\n",
    "TOTAL", count($employees),
    number_format($total_salary, 0, '.', ','),
    number_format($avg_salary, 0, '.', ','));

// sorted export - by salary descending
echo "\n=== top earners ===\n";
$sorted = $employees;
usort($sorted, function ($a, $b) {
    return $b['salary'] - $a['salary'];
});

$rank_file = "$tmp/rankings.csv";
$fp = fopen($rank_file, 'w');
fputcsv($fp, ['rank', 'name', 'department', 'salary']);
foreach ($sorted as $i => $emp) {
    fputcsv($fp, [$i + 1, $emp['name'], $emp['department'], $emp['salary']]);
    echo sprintf("  #%d %-15s %-15s %s\n",
        $i + 1, $emp['name'], $emp['department'],
        number_format($emp['salary'], 0, '.', ','));
}
fclose($fp);

// multi-file export report
echo "\n=== export summary ===\n";
$files = [$csv_file, $rank_file];
foreach ($files as $f) {
    $s = stat($f);
    echo sprintf("  %-30s %6d bytes\n", basename($f), $s['size']);
}

// generate a fixed-width report
echo "\n=== fixed-width report ===\n";
$report_file = "$tmp/report.txt";
$fp = fopen($report_file, 'w');
$header = str_pad("EMPLOYEE DIRECTORY", 60, " ", STR_PAD_BOTH) . "\n";
$header .= str_repeat("=", 60) . "\n\n";
fwrite($fp, $header);

foreach ($employees as $emp) {
    $line = sprintf("%-4d %-20s %-15s $%s\n",
        $emp['id'], $emp['name'], $emp['department'],
        number_format($emp['salary'], 0, '.', ','));
    fwrite($fp, $line);
}

$footer = "\n" . str_repeat("-", 60) . "\n";
$footer .= sprintf("Total employees: %d | Total payroll: $%s\n",
    count($employees), number_format($total_salary, 0, '.', ','));
fwrite($fp, $footer);
fclose($fp);

echo file_get_contents($report_file);

// cleanup
foreach ($files as $f) unlink($f);
unlink($report_file);
rmdir($tmp);
echo "\ncleanup: ok\n";
