<?php
// covers: explode, intval, in_array, range, array_merge, array_unique, sort, str_contains, preg_match, substr, strpos, date, mktime, checkdate, sprintf

function parseCronField(string $field, int $min, int $max): array {
    if ($field === '*') {
        return range($min, $max);
    }

    $values = [];

    $parts = explode(',', $field);
    foreach ($parts as $part) {
        $part = trim($part);

        // handle step: */5 or 1-10/2
        $step = 1;
        if (str_contains($part, '/')) {
            $stepParts = explode('/', $part);
            $part = $stepParts[0];
            $step = intval($stepParts[1]);
        }

        if ($part === '*') {
            for ($i = $min; $i <= $max; $i += $step) {
                $values[] = $i;
            }
        } elseif (str_contains($part, '-')) {
            $rangeParts = explode('-', $part);
            $start = intval($rangeParts[0]);
            $end = intval($rangeParts[1]);
            for ($i = $start; $i <= $end; $i += $step) {
                $values[] = $i;
            }
        } else {
            $values[] = intval($part);
        }
    }

    sort($values);
    return array_values(array_unique($values));
}

function parseCron(string $expr): array {
    $parts = preg_split('/\s+/', trim($expr));
    if (count($parts) !== 5) {
        return ['error' => 'Expected 5 fields'];
    }

    return [
        'minutes' => parseCronField($parts[0], 0, 59),
        'hours' => parseCronField($parts[1], 0, 23),
        'days' => parseCronField($parts[2], 1, 31),
        'months' => parseCronField($parts[3], 1, 12),
        'weekdays' => parseCronField($parts[4], 0, 6),
    ];
}

function cronMatches(array $parsed, int $minute, int $hour, int $day, int $month, int $weekday): bool {
    return in_array($minute, $parsed['minutes'])
        && in_array($hour, $parsed['hours'])
        && in_array($day, $parsed['days'])
        && in_array($month, $parsed['months'])
        && in_array($weekday, $parsed['weekdays']);
}

function describeCron(string $expr): string {
    $parsed = parseCron($expr);
    if (isset($parsed['error'])) {
        return $parsed['error'];
    }

    $parts = [];

    $minCount = count($parsed['minutes']);
    $hourCount = count($parsed['hours']);

    if ($minCount === 60 && $hourCount === 24) {
        $parts[] = "every minute";
    } elseif ($minCount === 1 && $hourCount === 1) {
        $parts[] = sprintf("at %02d:%02d", $parsed['hours'][0], $parsed['minutes'][0]);
    } elseif ($minCount === 1 && $hourCount === 24) {
        $parts[] = "every hour at minute " . $parsed['minutes'][0];
    } elseif ($hourCount === 1) {
        $parts[] = "at hour " . $parsed['hours'][0];
    }

    if (count($parsed['days']) < 31) {
        $parts[] = "on day(s) " . implode(',', $parsed['days']);
    }

    if (count($parsed['months']) < 12) {
        $monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        $names = array_map(function($m) use ($monthNames) { return $monthNames[$m]; }, $parsed['months']);
        $parts[] = "in " . implode(', ', $names);
    }

    if (count($parsed['weekdays']) < 7) {
        $dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        $names = array_map(function($d) use ($dayNames) { return $dayNames[$d]; }, $parsed['weekdays']);
        $parts[] = "on " . implode(', ', $names);
    }

    return empty($parts) ? "every minute" : implode(', ', $parts);
}

// --- tests ---

echo "Cron Field Parsing:\n";
echo "  '*' (0-59): " . implode(',', parseCronField('*', 0, 59)) . " (" . count(parseCronField('*', 0, 59)) . " values)\n";
echo "  '*/15' (0-59): " . implode(',', parseCronField('*/15', 0, 59)) . "\n";
echo "  '1-5' (0-59): " . implode(',', parseCronField('1-5', 0, 59)) . "\n";
echo "  '1,15,30' (0-59): " . implode(',', parseCronField('1,15,30', 0, 59)) . "\n";
echo "  '1-10/3' (0-59): " . implode(',', parseCronField('1-10/3', 0, 59)) . "\n";
echo "  '0-6' (0-6): " . implode(',', parseCronField('0-6', 0, 6)) . "\n";

echo "\nCron Expression Parsing:\n";
$expressions = [
    '* * * * *',
    '0 0 * * *',
    '*/15 * * * *',
    '0 9 * * 1-5',
    '30 2 1 * *',
    '0 0 1 1,6 *',
    '0 */2 * * *',
    '0 9-17 * * 1-5',
];

foreach ($expressions as $expr) {
    echo "  '$expr' -> " . describeCron($expr) . "\n";
}

echo "\nMatch Testing:\n";
$parsed = parseCron('0 9 * * 1-5');
$tests = [
    ['minute' => 0, 'hour' => 9, 'day' => 15, 'month' => 3, 'weekday' => 1, 'label' => 'Mon 9:00'],
    ['minute' => 0, 'hour' => 9, 'day' => 15, 'month' => 3, 'weekday' => 0, 'label' => 'Sun 9:00'],
    ['minute' => 30, 'hour' => 9, 'day' => 15, 'month' => 3, 'weekday' => 1, 'label' => 'Mon 9:30'],
    ['minute' => 0, 'hour' => 17, 'day' => 15, 'month' => 3, 'weekday' => 3, 'label' => 'Wed 17:00'],
];

foreach ($tests as $t) {
    $matches = cronMatches($parsed, $t['minute'], $t['hour'], $t['day'], $t['month'], $t['weekday']);
    echo "  " . $t['label'] . ": " . ($matches ? 'match' : 'no match') . "\n";
}

// --- date formatting ---

echo "\nDate Formatting:\n";
$ts = mktime(14, 30, 0, 6, 15, 2024);
echo "  timestamp: $ts\n";
echo "  Y-m-d: " . date('Y-m-d', $ts) . "\n";
echo "  H:i:s: " . date('H:i:s', $ts) . "\n";
echo "  D, d M Y: " . date('D, d M Y', $ts) . "\n";

echo "\nDate Validation:\n";
$dates = [
    [2024, 2, 29, 'leap year Feb 29'],
    [2023, 2, 29, 'non-leap Feb 29'],
    [2024, 4, 31, 'Apr 31'],
    [2024, 12, 31, 'Dec 31'],
];

foreach ($dates as $d) {
    $valid = checkdate($d[1], $d[2], $d[0]);
    echo "  " . $d[3] . " (" . $d[0] . "): " . ($valid ? 'valid' : 'invalid') . "\n";
}
