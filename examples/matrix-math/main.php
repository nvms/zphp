<?php
// covers: array_fill, count, array_map, array_sum, array_keys, number_format, str_pad, sprintf, abs, sqrt, round, pow

function matrixCreate(int $rows, int $cols, float $fill = 0.0): array {
    $m = [];
    for ($i = 0; $i < $rows; $i++) {
        $m[] = array_fill(0, $cols, $fill);
    }
    return $m;
}

function matrixIdentity(int $n): array {
    $m = matrixCreate($n, $n);
    for ($i = 0; $i < $n; $i++) {
        $m[$i][$i] = 1.0;
    }
    return $m;
}

function matrixMultiply(array $a, array $b): array {
    $rowsA = count($a);
    $colsA = count($a[0]);
    $colsB = count($b[0]);
    $result = matrixCreate($rowsA, $colsB);

    for ($i = 0; $i < $rowsA; $i++) {
        for ($j = 0; $j < $colsB; $j++) {
            $sum = 0.0;
            for ($k = 0; $k < $colsA; $k++) {
                $sum += $a[$i][$k] * $b[$k][$j];
            }
            $result[$i][$j] = $sum;
        }
    }
    return $result;
}

function matrixTranspose(array $m): array {
    $rows = count($m);
    $cols = count($m[0]);
    $result = matrixCreate($cols, $rows);
    for ($i = 0; $i < $rows; $i++) {
        for ($j = 0; $j < $cols; $j++) {
            $result[$j][$i] = $m[$i][$j];
        }
    }
    return $result;
}

function matrixAdd(array $a, array $b): array {
    $rows = count($a);
    $cols = count($a[0]);
    $result = matrixCreate($rows, $cols);
    for ($i = 0; $i < $rows; $i++) {
        for ($j = 0; $j < $cols; $j++) {
            $result[$i][$j] = $a[$i][$j] + $b[$i][$j];
        }
    }
    return $result;
}

function matrixScale(array $m, float $scalar): array {
    $rows = count($m);
    $cols = count($m[0]);
    $result = matrixCreate($rows, $cols);
    for ($i = 0; $i < $rows; $i++) {
        for ($j = 0; $j < $cols; $j++) {
            $result[$i][$j] = $m[$i][$j] * $scalar;
        }
    }
    return $result;
}

function matrixTrace(array $m): float {
    $n = min(count($m), count($m[0]));
    $sum = 0.0;
    for ($i = 0; $i < $n; $i++) {
        $sum += $m[$i][$i];
    }
    return $sum;
}

function det2x2(array $m): float {
    return $m[0][0] * $m[1][1] - $m[0][1] * $m[1][0];
}

function det3x3(array $m): float {
    return $m[0][0] * ($m[1][1] * $m[2][2] - $m[1][2] * $m[2][1])
         - $m[0][1] * ($m[1][0] * $m[2][2] - $m[1][2] * $m[2][0])
         + $m[0][2] * ($m[1][0] * $m[2][1] - $m[1][1] * $m[2][0]);
}

function vectorDot(array $a, array $b): float {
    $sum = 0.0;
    for ($i = 0; $i < count($a); $i++) {
        $sum += $a[$i] * $b[$i];
    }
    return $sum;
}

function vectorMagnitude(array $v): float {
    return sqrt(vectorDot($v, $v));
}

function vectorNormalize(array $v): array {
    $mag = vectorMagnitude($v);
    if ($mag == 0) return $v;
    return array_map(function($x) use ($mag) { return $x / $mag; }, $v);
}

function vectorCross(array $a, array $b): array {
    return [
        $a[1] * $b[2] - $a[2] * $b[1],
        $a[2] * $b[0] - $a[0] * $b[2],
        $a[0] * $b[1] - $a[1] * $b[0],
    ];
}

function printMatrix(string $name, array $m): void {
    echo "$name:\n";
    foreach ($m as $row) {
        echo "  [";
        $parts = [];
        foreach ($row as $val) {
            $parts[] = str_pad(number_format($val, 1), 7, ' ', STR_PAD_LEFT);
        }
        echo implode(', ', $parts);
        echo "]\n";
    }
}

// --- tests ---

$a = [[1, 2], [3, 4]];
$b = [[5, 6], [7, 8]];

printMatrix("A", $a);
printMatrix("B", $b);

$product = matrixMultiply($a, $b);
printMatrix("A * B", $product);

$sum = matrixAdd($a, $b);
printMatrix("A + B", $sum);

$scaled = matrixScale($a, 2.0);
printMatrix("A * 2", $scaled);

$transposed = matrixTranspose($a);
printMatrix("A^T", $transposed);

echo "\nTrace(A): " . number_format(matrixTrace($a), 1) . "\n";
echo "Det(A): " . number_format(det2x2($a), 1) . "\n";

// 3x3
$c = [[1, 2, 3], [4, 5, 6], [7, 8, 9]];
printMatrix("\nC (3x3)", $c);
echo "Det(C): " . number_format(det3x3($c), 1) . "\n";
echo "Trace(C): " . number_format(matrixTrace($c), 1) . "\n";

$d = [[2, 1, 1], [1, 3, 2], [1, 0, 0]];
echo "Det([[2,1,1],[1,3,2],[1,0,0]]): " . number_format(det3x3($d), 1) . "\n";

// identity
$i3 = matrixIdentity(3);
$ci = matrixMultiply($c, $i3);
printMatrix("\nC * I", $ci);

// vectors
echo "\nVectors:\n";
$v1 = [3, 4, 0];
$v2 = [1, 0, 0];

echo "  v1 = [" . implode(', ', $v1) . "]\n";
echo "  v2 = [" . implode(', ', $v2) . "]\n";
echo "  dot(v1, v2): " . number_format(vectorDot($v1, $v2), 1) . "\n";
echo "  |v1|: " . number_format(vectorMagnitude($v1), 4) . "\n";

$norm = vectorNormalize($v1);
$normStr = array_map(function($x) { return number_format($x, 4); }, $norm);
echo "  normalize(v1): [" . implode(', ', $normStr) . "]\n";
echo "  |normalize(v1)|: " . number_format(vectorMagnitude($norm), 4) . "\n";

$cross = vectorCross([1, 0, 0], [0, 1, 0]);
echo "  cross([1,0,0], [0,1,0]): [" . implode(', ', $cross) . "]\n";

// rotation matrix
echo "\n2D Rotation (90 degrees):\n";
$angle = M_PI / 2;
$rot = [
    [round(cos($angle), 4), round(-sin($angle), 4)],
    [round(sin($angle), 4), round(cos($angle), 4)],
];
$point = [[1], [0]];
$rotated = matrixMultiply($rot, $point);
echo "  [1, 0] rotated 90: [" . round($rotated[0][0], 4) . ", " . round($rotated[1][0], 4) . "]\n";
