<?php
// covers: str_getcsv, array_column, array_sum, array_map, number_format, str_pad, max, min, round, count, usort, array_slice, sprintf

$csvData = "name,department,salary,years
Alice,Engineering,95000,5
Bob,Marketing,72000,3
Charlie,Engineering,105000,8
Diana,Marketing,68000,2
Eve,Engineering,112000,10
Frank,Sales,78000,4
Grace,Sales,82000,6
Hank,Engineering,98000,7
Ivy,Marketing,71000,3";

$lines = explode("\n", $csvData);
$headers = str_getcsv(array_shift($lines));
$rows = [];
foreach ($lines as $line) {
    if (trim($line) === '') continue;
    $values = str_getcsv($line);
    $row = [];
    foreach ($headers as $i => $header) {
        $row[$header] = is_numeric($values[$i]) ? (int)$values[$i] : $values[$i];
    }
    $rows[] = $row;
}

echo "Employee Report\n";
echo str_repeat('=', 50) . "\n\n";

// department summary
$departments = [];
foreach ($rows as $row) {
    $dept = $row['department'];
    if (!array_key_exists($dept, $departments)) {
        $departments[$dept] = ['salaries' => [], 'years' => []];
    }
    $departments[$dept]['salaries'][] = $row['salary'];
    $departments[$dept]['years'][] = $row['years'];
}

echo "Department Summary:\n";
echo str_pad('Department', 15) . str_pad('Count', 8) . str_pad('Avg Salary', 14) . str_pad('Avg Years', 10) . "\n";
echo str_repeat('-', 47) . "\n";

ksort($departments);
foreach ($departments as $name => $data) {
    $count = count($data['salaries']);
    $avgSalary = array_sum($data['salaries']) / $count;
    $avgYears = round(array_sum($data['years']) / $count, 1);
    echo str_pad($name, 15)
        . str_pad((string)$count, 8)
        . str_pad('$' . number_format($avgSalary, 0), 14)
        . str_pad((string)$avgYears, 10)
        . "\n";
}

// top earners
echo "\nTop 3 Earners:\n";
usort($rows, function($a, $b) {
    return $b['salary'] - $a['salary'];
});

$top3 = array_slice($rows, 0, 3);
foreach ($top3 as $i => $row) {
    echo "  " . ($i + 1) . ". " . $row['name'] . " - $" . number_format($row['salary'], 0) . " (" . $row['department'] . ")\n";
}

// salary stats
$salaries = array_column($rows, 'salary');
$total = array_sum($salaries);
$avg = $total / count($salaries);
$maxSalary = max($salaries);
$minSalary = min($salaries);

echo "\nSalary Statistics:\n";
echo "  Total payroll: $" . number_format($total, 0) . "\n";
echo "  Average: $" . number_format($avg, 0) . "\n";
echo "  Highest: $" . number_format($maxSalary, 0) . "\n";
echo "  Lowest: $" . number_format($minSalary, 0) . "\n";
echo "  Range: $" . number_format($maxSalary - $minSalary, 0) . "\n";

// salary bands
echo "\nSalary Bands:\n";
$bands = ['Under $75K' => 0, '$75K-$100K' => 0, 'Over $100K' => 0];
foreach ($rows as $row) {
    if ($row['salary'] < 75000) {
        $bands['Under $75K']++;
    } elseif ($row['salary'] <= 100000) {
        $bands['$75K-$100K']++;
    } else {
        $bands['Over $100K']++;
    }
}

foreach ($bands as $band => $count) {
    $bar = str_repeat('#', $count * 3);
    echo "  " . str_pad($band, 12) . " $bar ($count)\n";
}

// formatted table
echo "\nFull Roster:\n";
echo sprintf("  %-10s %-14s %10s %6s\n", 'Name', 'Department', 'Salary', 'Years');
echo "  " . str_repeat('-', 42) . "\n";

usort($rows, function($a, $b) {
    $cmp = strcmp($a['department'], $b['department']);
    if ($cmp !== 0) return $cmp;
    return $b['salary'] - $a['salary'];
});

foreach ($rows as $row) {
    echo sprintf("  %-10s %-14s %10s %6d\n",
        $row['name'],
        $row['department'],
        '$' . number_format($row['salary'], 0),
        $row['years']
    );
}
