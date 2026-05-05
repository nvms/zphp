<?php
// covers: explode, implode, count, array_slice, array_reverse, array_merge,
//   sprintf, max, min, str_repeat, str_pad, preg_match, preg_match_all,
//   preg_replace, str_replace, substr, strlen, intdiv, abs, range,
//   array_fill, array_map, array_filter, ARRAY_FILTER_USE_BOTH

function lcs_table(array $a, array $b): array {
    $m = count($a);
    $n = count($b);
    $dp = array_fill(0, $m + 1, array_fill(0, $n + 1, 0));
    for ($i = 1; $i <= $m; $i++) {
        for ($j = 1; $j <= $n; $j++) {
            if ($a[$i - 1] === $b[$j - 1]) {
                $dp[$i][$j] = $dp[$i - 1][$j - 1] + 1;
            } else {
                $dp[$i][$j] = max($dp[$i - 1][$j], $dp[$i][$j - 1]);
            }
        }
    }
    return $dp;
}

function backtrack(array $dp, array $a, array $b): array {
    $ops = [];
    $i = count($a);
    $j = count($b);
    while ($i > 0 || $j > 0) {
        if ($i > 0 && $j > 0 && $a[$i - 1] === $b[$j - 1]) {
            $ops[] = ['eq', $a[$i - 1]];
            $i--;
            $j--;
        } elseif ($j > 0 && ($i === 0 || $dp[$i][$j - 1] >= $dp[$i - 1][$j])) {
            $ops[] = ['add', $b[$j - 1]];
            $j--;
        } else {
            $ops[] = ['del', $a[$i - 1]];
            $i--;
        }
    }
    return array_reverse($ops);
}

function unified_diff(string $a, string $b, int $context = 3): string {
    $a_lines = $a === '' ? [] : explode("\n", $a);
    $b_lines = $b === '' ? [] : explode("\n", $b);
    $dp = lcs_table($a_lines, $b_lines);
    $ops = backtrack($dp, $a_lines, $b_lines);

    // group ops into hunks based on context
    $hunks = [];
    $cur = null;
    $a_pos = 1;
    $b_pos = 1;
    $idle = 0;

    foreach ($ops as $idx => [$tag, $line]) {
        if ($tag === 'eq') {
            if ($cur !== null) {
                $cur['ops'][] = [$tag, $line, $a_pos, $b_pos];
                $idle++;
                if ($idle > $context * 2) {
                    // close hunk, trim trailing context
                    $trim = $idle - $context;
                    $cur['ops'] = array_slice($cur['ops'], 0, count($cur['ops']) - $trim);
                    $hunks[] = $cur;
                    $cur = null;
                    $idle = 0;
                }
            }
            $a_pos++;
            $b_pos++;
        } else {
            if ($cur === null) {
                // open new hunk with leading context
                $start = max(0, count($hunks) > 0 ? 0 : 0);
                $back = min($context, $idle);
                $cur = ['ops' => [], 'a_start' => $a_pos - $back, 'b_start' => $b_pos - $back];
                // gather leading context from previous eq ops we may have skipped
                $leading = [];
                $look_back = $back;
                for ($k = $idx - 1; $k >= 0 && $look_back > 0; $k--) {
                    if ($ops[$k][0] === 'eq') {
                        $leading[] = $ops[$k];
                        $look_back--;
                    } else {
                        break;
                    }
                }
                $leading = array_reverse($leading);
                $a_lead = $a_pos - count($leading);
                $b_lead = $b_pos - count($leading);
                foreach ($leading as $le) {
                    $cur['ops'][] = ['eq', $le[1], $a_lead, $b_lead];
                    $a_lead++;
                    $b_lead++;
                }
            }
            $idle = 0;
            if ($tag === 'del') {
                $cur['ops'][] = [$tag, $line, $a_pos, $b_pos];
                $a_pos++;
            } else {
                $cur['ops'][] = [$tag, $line, $a_pos, $b_pos];
                $b_pos++;
            }
        }
    }
    if ($cur !== null) {
        $trim = max(0, $idle - $context);
        if ($trim > 0) {
            $cur['ops'] = array_slice($cur['ops'], 0, count($cur['ops']) - $trim);
        }
        $hunks[] = $cur;
    }

    if (empty($hunks)) return '';

    $out = '';
    foreach ($hunks as $h) {
        $a_lines_count = count(array_filter($h['ops'], fn($o) => $o[0] === 'eq' || $o[0] === 'del'));
        $b_lines_count = count(array_filter($h['ops'], fn($o) => $o[0] === 'eq' || $o[0] === 'add'));
        $out .= sprintf("@@ -%d,%d +%d,%d @@\n", $h['a_start'], $a_lines_count, $h['b_start'], $b_lines_count);
        foreach ($h['ops'] as [$tag, $line]) {
            $prefix = match ($tag) { 'eq' => ' ', 'add' => '+', 'del' => '-' };
            $out .= $prefix . $line . "\n";
        }
    }
    return $out;
}

echo "=== identical input ===\n";
echo unified_diff("a\nb\nc", "a\nb\nc") ?: "(no diff)\n";

echo "\n=== single line change ===\n";
$a = "alpha\nbeta\ngamma\ndelta\nepsilon";
$b = "alpha\nBETA\ngamma\ndelta\nepsilon";
echo unified_diff($a, $b);

echo "\n=== insertion ===\n";
$a = "one\ntwo\nthree";
$b = "one\ntwo\nNEW\nthree";
echo unified_diff($a, $b);

echo "\n=== deletion ===\n";
$a = "one\ntwo\nthree\nfour";
$b = "one\nthree\nfour";
echo unified_diff($a, $b);

echo "\n=== completely different ===\n";
$a = "aaa\nbbb\nccc";
$b = "xxx\nyyy\nzzz";
echo unified_diff($a, $b);

echo "\n=== empty to content ===\n";
echo unified_diff("", "added\nlines\nhere");

echo "\n=== content to empty ===\n";
echo unified_diff("removed\nall\nlines", "");

echo "\n=== many small changes ===\n";
$a = implode("\n", range(1, 15));
$b = "1\n2\n3-changed\n4\n5\n6\n7-changed\n8\n9\n10\n11\n12-changed\n13\n14\n15";
echo unified_diff($a, $b);

echo "\n=== context boundary (small ctx) ===\n";
$a = "a\nb\nc\nd\ne\nf\ng\nh\ni\nj";
$b = "a\nb\nc\nD\ne\nf\ng\nH\ni\nj";
echo unified_diff($a, $b, 1);

echo "\n=== whitespace-only change ===\n";
echo unified_diff("hello", "hello ");

echo "\n=== diff stats ===\n";
function diff_stats(string $a, string $b): array {
    $diff = unified_diff($a, $b);
    if ($diff === '') return ['add' => 0, 'del' => 0, 'hunks' => 0];
    $add = preg_match_all('/^\+(?!\+\+)/m', $diff);
    $del = preg_match_all('/^-(?!--)/m', $diff);
    $hunks = preg_match_all('/^@@ /m', $diff);
    return ['add' => $add, 'del' => $del, 'hunks' => $hunks];
}
$cases = [
    ['unchanged', 'foo', 'foo'],
    ['one add', 'a\nb', 'a\nb\nc'],
    ['one del', 'a\nb\nc', 'a\nb'],
    ['rewrite', 'a\nb\nc', 'x\ny\nz'],
    ['mid swap', "1\n2\n3\n4\n5", "1\n2\nNEW\n4\n5"],
];
foreach ($cases as [$name, $x, $y]) {
    $stats = diff_stats(str_replace('\n', "\n", $x), str_replace('\n', "\n", $y));
    echo sprintf("  %-12s +%d -%d hunks=%d\n", $name, $stats['add'], $stats['del'], $stats['hunks']);
}

echo "\n=== diff is itself a valid unified diff format ===\n";
$d = unified_diff("a\nb\nc\nd\ne", "a\nB\nc\nD\ne");
$lines = explode("\n", rtrim($d, "\n"));
$header_count = 0;
foreach ($lines as $l) {
    if (preg_match('/^@@ -(\d+),(\d+) \+(\d+),(\d+) @@$/', $l) === 1) $header_count++;
}
echo "  hunk headers: $header_count\n";
echo "  total lines: " . count($lines) . "\n";

echo "\n=== applying a parsed diff (sanity) ===\n";
// extract +/- counts to verify shapes
$d = unified_diff("aaa\nbbb\nccc\nddd\neee", "aaa\nBBB\nccc\nDDD\neee");
preg_match_all('/^@@ -(\d+),(\d+) \+(\d+),(\d+) @@/m', $d, $headers, PREG_SET_ORDER);
foreach ($headers as $h) {
    echo "  hunk: a=$h[1],$h[2] b=$h[3],$h[4]\n";
}
