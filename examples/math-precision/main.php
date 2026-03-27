<?php
// covers: fdiv, intdiv, round, number_format, base_convert, log, log10,
//   hypot, abs, floor, ceil, fmod, pow, sqrt, is_nan, is_infinite, is_finite,
//   bindec, decoct, octdec, hexdec, dechex, sprintf, pi, min, max

// fdiv: safe division handling
echo "=== fdiv (safe division) ===\n";
$cases = [
    [10, 3, '10/3'],
    [1, 0, '1/0'],
    [-1, 0, '-1/0'],
    [0, 0, '0/0'],
];
foreach ($cases as $case) {
    $result = fdiv($case[0], $case[1]);
    $type = is_nan($result) ? 'NAN' : (is_infinite($result) ? 'INF' : 'finite');
    $display = is_nan($result) ? 'NAN' : (is_infinite($result) ? ($result < 0 ? '-INF' : 'INF') : (string)$result);
    echo sprintf("  %-12s = %-20s (%s)\n", $case[2], $display, $type);
}

// intdiv: integer division
echo "\n=== intdiv ===\n";
$pairs = [[7, 2], [10, 3], [-7, 2], [0, 5], [100, 7]];
foreach ($pairs as $pair) {
    $q = intdiv($pair[0], $pair[1]);
    $r = $pair[0] % $pair[1];
    echo sprintf("  %4d / %2d = %3d remainder %2d  (verify: %d)\n",
        $pair[0], $pair[1], $q, $r, $q * $pair[1] + $r);
}

// base conversion
echo "\n=== base conversion ===\n";
$number = 255;
echo "decimal $number in different bases:\n";
echo "  binary:  " . decbin($number) . "\n";
echo "  octal:   " . decoct($number) . "\n";
echo "  hex:     " . dechex($number) . "\n";
echo "  base36:  " . base_convert((string)$number, 10, 36) . "\n";

echo "\nconversions back:\n";
echo "  bindec('11111111') = " . bindec('11111111') . "\n";
echo "  octdec('377')      = " . octdec('377') . "\n";
echo "  hexdec('ff')       = " . hexdec('ff') . "\n";
echo "  base36 '73' -> 10  = " . base_convert('73', 36, 10) . "\n";

// color math with hex
echo "\n=== color math ===\n";
function hexToRgb(string $hex): array {
    $hex = ltrim($hex, '#');
    return [
        'r' => hexdec(substr($hex, 0, 2)),
        'g' => hexdec(substr($hex, 2, 2)),
        'b' => hexdec(substr($hex, 4, 2)),
    ];
}

function rgbToHex(int $r, int $g, int $b): string {
    return '#' . str_pad(dechex($r), 2, '0', STR_PAD_LEFT)
        . str_pad(dechex($g), 2, '0', STR_PAD_LEFT)
        . str_pad(dechex($b), 2, '0', STR_PAD_LEFT);
}

function blendColors(string $c1, string $c2, float $ratio): string {
    $a = hexToRgb($c1);
    $b = hexToRgb($c2);
    $r = (int)round($a['r'] * (1 - $ratio) + $b['r'] * $ratio);
    $g = (int)round($a['g'] * (1 - $ratio) + $b['g'] * $ratio);
    $b_val = (int)round($a['b'] * (1 - $ratio) + $b['b'] * $ratio);
    return rgbToHex($r, $g, $b_val);
}

$red = '#ff0000';
$blue = '#0000ff';
echo "blending $red and $blue:\n";
for ($r = 0.0; $r <= 1.0; $r += 0.25) {
    echo sprintf("  %.0f%%: %s\n", $r * 100, blendColors($red, $blue, $r));
}

// logarithms and scientific calculations
echo "\n=== logarithms ===\n";
$values = [1, 2, 10, 100, 1024, 65536];
echo sprintf("  %-8s %8s %8s %8s\n", "value", "log2", "log10", "ln");
foreach ($values as $v) {
    echo sprintf("  %-8d %8.4f %8.4f %8.4f\n", $v, log($v) / log(2), log10($v), log($v));
}

// pythagorean calculations with hypot
echo "\n=== hypot (pythagorean) ===\n";
$triangles = [[3, 4], [5, 12], [8, 15], [7, 24]];
foreach ($triangles as $t) {
    $h = hypot($t[0], $t[1]);
    echo sprintf("  sides %2d, %2d -> hypotenuse = %.4f\n", $t[0], $t[1], $h);
}

// distance between 2D points
function distance(float $x1, float $y1, float $x2, float $y2): float {
    return hypot($x2 - $x1, $y2 - $y1);
}

echo "\npoint distances:\n";
$points = [[0, 0, 3, 4], [1, 1, 4, 5], [-3, -4, 0, 0]];
foreach ($points as $p) {
    $d = distance($p[0], $p[1], $p[2], $p[3]);
    echo sprintf("  (%.0f,%.0f) to (%.0f,%.0f) = %.4f\n", $p[0], $p[1], $p[2], $p[3], $d);
}

// rounding modes
echo "\n=== rounding ===\n";
$nums = [2.5, 3.5, 4.5, -2.5, 2.55, 2.449];
echo sprintf("  %-8s %8s %8s %8s %8s\n", "value", "round", "floor", "ceil", "round2");
foreach ($nums as $n) {
    echo sprintf("  %-8s %8s %8s %8s %8s\n",
        $n, round($n), floor($n), ceil($n), round($n, 1));
}

// financial calculations with number_format
echo "\n=== financial formatting ===\n";
$prices = [1234.5, 1000000, 0.99, 42195.876, 0.001];
foreach ($prices as $price) {
    echo sprintf("  %15s -> %s\n",
        $price,
        number_format($price, 2, '.', ','));
}

// fmod for precise remainder
echo "\n=== fmod ===\n";
$fmod_cases = [[10.5, 3.2], [2.5, 0.5], [7.0, 2.5], [-5.5, 3.0]];
foreach ($fmod_cases as $case) {
    echo sprintf("  fmod(%.1f, %.1f) = %.4f\n", $case[0], $case[1], fmod($case[0], $case[1]));
}
