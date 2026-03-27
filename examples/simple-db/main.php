<?php
// covers: array_column, array_filter, array_map, array_values, array_keys, array_unique, array_count_values, array_sum, array_product, usort, uasort, array_slice, array_chunk, array_splice, array_search, compact, extract, array_walk, array_fill, in_array, count, implode, sprintf, str_pad, strtolower, strtoupper, preg_match, min, max, round, number_format

// --- in-memory table ---

$employees = [
    ['id' => 1, 'name' => 'Alice',   'dept' => 'Engineering', 'salary' => 95000, 'active' => true],
    ['id' => 2, 'name' => 'Bob',     'dept' => 'Marketing',   'salary' => 72000, 'active' => true],
    ['id' => 3, 'name' => 'Charlie', 'dept' => 'Engineering', 'salary' => 110000, 'active' => true],
    ['id' => 4, 'name' => 'Diana',   'dept' => 'Marketing',   'salary' => 68000, 'active' => false],
    ['id' => 5, 'name' => 'Eve',     'dept' => 'Engineering', 'salary' => 105000, 'active' => true],
    ['id' => 6, 'name' => 'Frank',   'dept' => 'Sales',       'salary' => 82000, 'active' => true],
    ['id' => 7, 'name' => 'Grace',   'dept' => 'Sales',       'salary' => 78000, 'active' => true],
    ['id' => 8, 'name' => 'Hank',    'dept' => 'Engineering', 'salary' => 98000, 'active' => false],
    ['id' => 9, 'name' => 'Ivy',     'dept' => 'Marketing',   'salary' => 75000, 'active' => true],
    ['id' => 10, 'name' => 'Jack',   'dept' => 'Sales',       'salary' => 91000, 'active' => true],
];

// --- SELECT (array_column) ---

echo "All names:\n";
$names = array_column($employees, 'name');
echo implode(", ", $names) . "\n";

// keyed by id
$name_by_id = array_column($employees, 'name', 'id');
echo "Employee 3: " . $name_by_id[3] . "\n";
echo "Employee 7: " . $name_by_id[7] . "\n";

// --- WHERE (array_filter) ---

echo "\nActive engineers:\n";
$active_eng = array_filter($employees, function($e) {
    return $e['active'] && $e['dept'] === 'Engineering';
});
foreach ($active_eng as $e) {
    echo "  " . $e['name'] . " - $" . number_format($e['salary']) . "\n";
}

// filter with regex
echo "\nNames starting with vowels:\n";
$vowel_names = array_filter($employees, function($e) {
    return preg_match('/^[AEIOU]/i', $e['name']);
});
foreach ($vowel_names as $e) {
    echo "  " . $e['name'] . "\n";
}

// --- ORDER BY (usort) ---

echo "\nTop earners:\n";
$sorted = $employees;
usort($sorted, function($a, $b) {
    return $b['salary'] - $a['salary'];
});
foreach (array_slice($sorted, 0, 3) as $e) {
    echo "  " . str_pad($e['name'], 10) . " $" . number_format($e['salary']) . "\n";
}

// multi-column sort: dept ASC, salary DESC
echo "\nSorted by dept, salary desc:\n";
$multi = $employees;
usort($multi, function($a, $b) {
    $dept_cmp = strcmp($a['dept'], $b['dept']);
    if ($dept_cmp !== 0) return $dept_cmp;
    return $b['salary'] - $a['salary'];
});
foreach ($multi as $e) {
    echo "  " . str_pad($e['dept'], 13) . str_pad($e['name'], 10) . "$" . number_format($e['salary']) . "\n";
}

// --- GROUP BY (manual aggregation) ---

echo "\nDepartment stats:\n";
$depts = array_unique(array_column($employees, 'dept'));
sort($depts);
foreach ($depts as $dept) {
    $dept_emps = array_filter($employees, function($e) use ($dept) {
        return $e['dept'] === $dept;
    });
    $salaries = array_column(array_values($dept_emps), 'salary');
    $count = count($salaries);
    $total = array_sum($salaries);
    $avg = round($total / $count);
    $min_sal = min(...$salaries);
    $max_sal = max(...$salaries);

    echo "  $dept:\n";
    echo "    Count: $count\n";
    echo "    Avg salary: $" . number_format($avg) . "\n";
    echo "    Range: $" . number_format($min_sal) . " - $" . number_format($max_sal) . "\n";
}

// --- DISTINCT ---

echo "\nDistinct departments: ";
echo implode(", ", $depts) . "\n";

// --- COUNT with condition ---

$active_count = count(array_filter($employees, function($e) { return $e['active']; }));
$inactive_count = count($employees) - $active_count;
echo "Active: $active_count, Inactive: $inactive_count\n";

// --- array_count_values ---

echo "\nEmployees per department:\n";
$dept_counts = array_count_values(array_column($employees, 'dept'));
arsort($dept_counts);
foreach ($dept_counts as $dept => $count) {
    echo "  $dept: $count\n";
}

// --- HAVING (filter aggregated results) ---

echo "\nDepartments with avg salary > 80000:\n";
foreach ($depts as $dept) {
    $dept_emps = array_filter($employees, function($e) use ($dept) {
        return $e['dept'] === $dept;
    });
    $salaries = array_column(array_values($dept_emps), 'salary');
    $avg = array_sum($salaries) / count($salaries);
    if ($avg > 80000) {
        echo "  $dept: $" . number_format(round($avg)) . "\n";
    }
}

// --- UPDATE (array_walk) ---

echo "\nAfter 10% raise for sales:\n";
$updated = $employees;
array_walk($updated, function(&$e) {
    if ($e['dept'] === 'Sales') {
        $e['salary'] = (int)($e['salary'] * 1.1);
    }
});
$sales = array_filter($updated, function($e) { return $e['dept'] === 'Sales'; });
foreach ($sales as $e) {
    echo "  " . $e['name'] . " - $" . number_format($e['salary']) . "\n";
}

// --- JOIN (merge two tables) ---

echo "\nJoined data:\n";
$projects = [
    ['emp_id' => 1, 'project' => 'API Redesign'],
    ['emp_id' => 3, 'project' => 'Database Migration'],
    ['emp_id' => 5, 'project' => 'API Redesign'],
    ['emp_id' => 6, 'project' => 'Q1 Campaign'],
    ['emp_id' => 1, 'project' => 'Infrastructure'],
];

$emp_lookup = array_column($employees, null, 'id');
foreach ($projects as $p) {
    $emp = $emp_lookup[$p['emp_id']];
    echo "  " . str_pad($emp['name'], 10) . $p['project'] . "\n";
}

// --- LIMIT/OFFSET (array_slice) ---

echo "\nPage 2 (3 per page):\n";
$page = array_slice($employees, 3, 3);
foreach ($page as $e) {
    echo "  " . $e['id'] . ". " . $e['name'] . "\n";
}

// --- compact/extract round-trip ---

echo "\nCompact/extract:\n";
$name = "TestUser";
$role = "admin";
$level = 5;
$record = compact('name', 'role', 'level');
echo "Compact: ";
foreach ($record as $k => $v) {
    echo "$k=$v ";
}
echo "\n";

extract($record);
echo "Extract: name=$name, role=$role, level=$level\n";

// --- array_search ---

echo "\nSearch:\n";
$names = array_column($employees, 'name');
$idx = array_search('Eve', $names);
echo "Eve is at index: $idx\n";
$missing = array_search('Zoe', $names);
echo "Zoe found: " . ($missing === false ? "no" : "yes") . "\n";

// --- array_chunk for batch processing ---

echo "\nBatch processing (chunks of 3):\n";
$chunks = array_chunk($employees, 3);
foreach ($chunks as $i => $chunk) {
    $names = array_column($chunk, 'name');
    echo "  Batch " . ($i + 1) . ": " . implode(", ", $names) . "\n";
}

// --- table display ---

echo "\nEmployee table:\n";
$header = sprintf("%-4s %-10s %-13s %10s %s", "ID", "Name", "Dept", "Salary", "Status");
echo $header . "\n";
echo str_repeat("-", strlen($header)) . "\n";
foreach ($employees as $e) {
    echo sprintf("%-4d %-10s %-13s %10s %s",
        $e['id'],
        $e['name'],
        $e['dept'],
        "$" . number_format($e['salary']),
        $e['active'] ? "Active" : "Inactive"
    ) . "\n";
}
