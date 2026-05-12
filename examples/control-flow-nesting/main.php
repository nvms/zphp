<?php
// covers: deeply nested control flow - 4-deep foreach by-ref, nested switch,
//   nested match, try-catch-finally cascades, generator yielding through refs,
//   recursive closures, captured-by-ref accumulators

echo "=== 4-deep nested foreach by-ref ===\n";
$grid = [[[[1, 2], [3, 4]], [[5, 6]]]];
foreach ($grid as &$d1) {
    foreach ($d1 as &$d2) {
        foreach ($d2 as &$d3) {
            foreach ($d3 as &$d4) {
                $d4 *= 10;
            }
            unset($d4);
        }
        unset($d3);
    }
    unset($d2);
}
unset($d1);
print_r($grid);

echo "=== mixed-keyed nesting (by-ref + key destructure) ===\n";
$data = ['g1' => ['a' => 1, 'b' => 2], 'g2' => ['c' => 3]];
foreach ($data as $gk => &$group) {
    foreach ($group as $k => &$v) {
        $v = "$gk:$k:$v";
    }
    unset($v);
}
unset($group);
print_r($data);

echo "=== nested switch ===\n";
function classify(int $a, int $b): string {
    switch ($a) {
        case 1:
            switch ($b) {
                case 10: return "1+10";
                case 20: return "1+20";
                default: return "1+?";
            }
        case 2:
            switch ($b) {
                case 10: return "2+10";
                default: return "2+?";
            }
    }
    return "?";
}
foreach ([[1,10],[1,20],[2,10],[2,99],[9,10]] as [$a, $b]) {
    echo "$a,$b -> " . classify($a, $b) . "\n";
}

echo "\n=== nested match ===\n";
function describe(array $m): array {
    $out = [];
    foreach ($m as $row) {
        $out[] = match (true) {
            count($row) === 0 => 'empty',
            default => match ($row[0]) {
                0 => 'zero-start',
                1 => 'one-start',
                default => 'other-start',
            },
        };
    }
    return $out;
}
print_r(describe([[0,1], [1,2,3], [5], [], [99]]));

echo "=== try/catch/finally nested ===\n";
function nested(): array {
    $log = [];
    try {
        $log[] = 'outer-try';
        try {
            $log[] = 'inner-try';
            throw new RuntimeException('inner');
        } catch (Exception $e) {
            $log[] = 'inner-catch: ' . $e->getMessage();
            throw new LogicException('rethrown');
        } finally {
            $log[] = 'inner-finally';
        }
    } catch (LogicException $e) {
        $log[] = 'outer-catch: ' . $e->getMessage();
    } finally {
        $log[] = 'outer-finally';
    }
    return $log;
}
print_r(nested());

echo "=== throw in finally overrides return ===\n";
function tryFinally(): string {
    try {
        try {
            return 'try-result';
        } finally {
            throw new RuntimeException('finally throws');
        }
    } catch (Exception $e) {
        return 'caught: ' . $e->getMessage();
    }
}
echo tryFinally() . "\n";

echo "\n=== recursive closure via use(&\$fact) ===\n";
$fact = null;
$fact = function (int $n) use (&$fact): int {
    return $n <= 1 ? 1 : $n * $fact($n - 1);
};
echo "5! = " . $fact(5) . "\n";
echo "10! = " . $fact(10) . "\n";

echo "\n=== captured-by-ref accumulator object ===\n";
function makeAcc(): array {
    $sum = 0;
    return [
        'add'   => function ($n) use (&$sum) { $sum += $n; },
        'get'   => function () use (&$sum) { return $sum; },
        'reset' => function () use (&$sum) { $sum = 0; },
    ];
}
$acc = makeAcc();
$acc['add'](5); $acc['add'](10); $acc['add'](7);
echo "sum: " . $acc['get']() . "\n";
$acc['reset']();
echo "after reset: " . $acc['get']() . "\n";

echo "\n=== generator yields ref values across loop body ===\n";
function take(iterable $src, int $n): array {
    $out = [];
    foreach ($src as $v) {
        if (count($out) >= $n) break;
        $out[] = $v;
    }
    return $out;
}
function squares(): Generator {
    for ($i = 1; ; $i++) yield $i * $i;
}
print_r(take(squares(), 5));

echo "=== switch inside foreach updating outer state ===\n";
$buckets = ['low' => 0, 'high' => 0];
foreach ([3, 7, 1, 8, 2, 9, 5] as $n) {
    switch (true) {
        case $n < 5: $buckets['low']++; break;
        default:     $buckets['high']++; break;
    }
}
print_r($buckets);

echo "done\n";
