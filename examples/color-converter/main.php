<?php
// covers: hexdec, dechex, str_pad, substr, round, max, min, abs, fmod, floor, intval, sprintf, number_format, array_map

function hexToRgb(string $hex): array {
    $hex = ltrim($hex, '#');
    if (strlen($hex) === 3) {
        $hex = $hex[0] . $hex[0] . $hex[1] . $hex[1] . $hex[2] . $hex[2];
    }
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

function rgbToHsl(int $r, int $g, int $b): array {
    $r /= 255;
    $g /= 255;
    $b /= 255;

    $max = max($r, $g, $b);
    $min = min($r, $g, $b);
    $l = ($max + $min) / 2;

    if ($max === $min) {
        return ['h' => 0, 's' => 0, 'l' => round($l * 100)];
    }

    $d = $max - $min;
    $s = $l > 0.5 ? $d / (2 - $max - $min) : $d / ($max + $min);

    if ($max === $r) {
        $h = (($g - $b) / $d) + ($g < $b ? 6 : 0);
    } elseif ($max === $g) {
        $h = (($b - $r) / $d) + 2;
    } else {
        $h = (($r - $g) / $d) + 4;
    }

    $h = round($h * 60);
    $s = round($s * 100);
    $l = round($l * 100);

    return ['h' => (int)$h, 's' => (int)$s, 'l' => (int)$l];
}

function hslToRgb(int $h, int $s, int $l): array {
    $h /= 360;
    $s /= 100;
    $l /= 100;

    if ($s == 0) {
        $v = (int)round($l * 255);
        return ['r' => $v, 'g' => $v, 'b' => $v];
    }

    $q = $l < 0.5 ? $l * (1 + $s) : $l + $s - $l * $s;
    $p = 2 * $l - $q;

    $r = hueToRgb($p, $q, $h + 1/3);
    $g = hueToRgb($p, $q, $h);
    $b = hueToRgb($p, $q, $h - 1/3);

    return [
        'r' => (int)round($r * 255),
        'g' => (int)round($g * 255),
        'b' => (int)round($b * 255),
    ];
}

function hueToRgb(float $p, float $q, float $t): float {
    if ($t < 0) $t += 1;
    if ($t > 1) $t -= 1;
    if ($t < 1/6) return $p + ($q - $p) * 6 * $t;
    if ($t < 1/2) return $q;
    if ($t < 2/3) return $p + ($q - $p) * (2/3 - $t) * 6;
    return $p;
}

function luminance(int $r, int $g, int $b): float {
    $rs = $r / 255;
    $gs = $g / 255;
    $bs = $b / 255;
    $rs = $rs <= 0.03928 ? $rs / 12.92 : pow(($rs + 0.055) / 1.055, 2.4);
    $gs = $gs <= 0.03928 ? $gs / 12.92 : pow(($gs + 0.055) / 1.055, 2.4);
    $bs = $bs <= 0.03928 ? $bs / 12.92 : pow(($bs + 0.055) / 1.055, 2.4);
    return 0.2126 * $rs + 0.7152 * $gs + 0.0722 * $bs;
}

function contrastRatio(string $hex1, string $hex2): float {
    $c1 = hexToRgb($hex1);
    $c2 = hexToRgb($hex2);
    $l1 = luminance($c1['r'], $c1['g'], $c1['b']);
    $l2 = luminance($c2['r'], $c2['g'], $c2['b']);
    $lighter = max($l1, $l2);
    $darker = min($l1, $l2);
    return round(($lighter + 0.05) / ($darker + 0.05), 2);
}

function blendColors(string $hex1, string $hex2, float $ratio = 0.5): string {
    $c1 = hexToRgb($hex1);
    $c2 = hexToRgb($hex2);
    $r = (int)round($c1['r'] * (1 - $ratio) + $c2['r'] * $ratio);
    $g = (int)round($c1['g'] * (1 - $ratio) + $c2['g'] * $ratio);
    $b = (int)round($c1['b'] * (1 - $ratio) + $c2['b'] * $ratio);
    return rgbToHex($r, $g, $b);
}

// --- tests ---

echo "Hex to RGB:\n";
$colors = ['#ff0000', '#00ff00', '#0000ff', '#ffffff', '#000000', '#ff8c00'];
foreach ($colors as $hex) {
    $rgb = hexToRgb($hex);
    echo "  $hex -> rgb(" . $rgb['r'] . ", " . $rgb['g'] . ", " . $rgb['b'] . ")\n";
}

echo "\nRGB to Hex:\n";
echo "  (255, 0, 0) -> " . rgbToHex(255, 0, 0) . "\n";
echo "  (0, 128, 255) -> " . rgbToHex(0, 128, 255) . "\n";
echo "  (64, 64, 64) -> " . rgbToHex(64, 64, 64) . "\n";

echo "\nShorthand hex:\n";
$rgb = hexToRgb('#f0c');
echo "  #f0c -> rgb(" . $rgb['r'] . ", " . $rgb['g'] . ", " . $rgb['b'] . ")\n";

echo "\nRGB to HSL:\n";
$testColors = [
    ['name' => 'Red', 'r' => 255, 'g' => 0, 'b' => 0],
    ['name' => 'Green', 'r' => 0, 'g' => 255, 'b' => 0],
    ['name' => 'Blue', 'r' => 0, 'g' => 0, 'b' => 255],
    ['name' => 'Orange', 'r' => 255, 'g' => 165, 'b' => 0],
];
foreach ($testColors as $c) {
    $hsl = rgbToHsl($c['r'], $c['g'], $c['b']);
    echo "  " . $c['name'] . " -> hsl(" . $hsl['h'] . ", " . $hsl['s'] . "%, " . $hsl['l'] . "%)\n";
}

echo "\nHSL to RGB:\n";
$rgb = hslToRgb(0, 100, 50);
echo "  hsl(0, 100%, 50%) -> rgb(" . $rgb['r'] . ", " . $rgb['g'] . ", " . $rgb['b'] . ")\n";
$rgb = hslToRgb(120, 100, 50);
echo "  hsl(120, 100%, 50%) -> rgb(" . $rgb['r'] . ", " . $rgb['g'] . ", " . $rgb['b'] . ")\n";
$rgb = hslToRgb(240, 100, 50);
echo "  hsl(240, 100%, 50%) -> rgb(" . $rgb['r'] . ", " . $rgb['g'] . ", " . $rgb['b'] . ")\n";

echo "\nContrast Ratios:\n";
$pairs = [
    ['#000000', '#ffffff', 'Black/White'],
    ['#000000', '#777777', 'Black/Gray'],
    ['#ff0000', '#ffffff', 'Red/White'],
    ['#0000ff', '#ffffff', 'Blue/White'],
];
foreach ($pairs as $pair) {
    $ratio = contrastRatio($pair[0], $pair[1]);
    $grade = $ratio >= 7 ? 'AAA' : ($ratio >= 4.5 ? 'AA' : 'Fail');
    echo "  " . $pair[2] . ": " . number_format($ratio, 2) . ":1 ($grade)\n";
}

echo "\nColor Blending:\n";
echo "  Red + Blue (50%): " . blendColors('#ff0000', '#0000ff') . "\n";
echo "  Red + Blue (25%): " . blendColors('#ff0000', '#0000ff', 0.25) . "\n";
echo "  Red + Blue (75%): " . blendColors('#ff0000', '#0000ff', 0.75) . "\n";
echo "  Black + White: " . blendColors('#000000', '#ffffff') . "\n";
