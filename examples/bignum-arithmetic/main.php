<?php
// covers: GMP arbitrary precision (gmp_init, gmp_add/sub/mul/pow, gmp_strval,
//   gmp_cmp, gmp_mod, gmp_gcd, gmp_invert), bcmath fixed-point math
//   (bcadd, bcsub, bcmul, bcdiv, bcpow, bccomp, bcscale)

echo "=== GMP: massive factorial ===\n";
function fact_big(int $n): GMP {
    $acc = gmp_init(1);
    for ($i = 2; $i <= $n; $i++) {
        $acc = gmp_mul($acc, $i);
    }
    return $acc;
}
$f30 = fact_big(30);
echo "30! = " . gmp_strval($f30) . "\n";
echo "digit count: " . strlen(gmp_strval($f30)) . "\n";

echo "\n=== GMP: powers ===\n";
$a = gmp_pow(2, 200);
echo "2^200 = " . gmp_strval($a) . "\n";
echo "digits: " . strlen(gmp_strval($a)) . "\n";

echo "\n=== GMP: modular inverse (used in crypto) ===\n";
$a = gmp_init(17);
$m = gmp_init(101);
$inv = gmp_invert($a, $m);
echo "17^-1 mod 101 = " . gmp_strval($inv) . "\n";
$check = gmp_mod(gmp_mul($a, $inv), $m);
echo "check 17 * inv mod 101 = " . gmp_strval($check) . "\n";

echo "\n=== GMP: gcd of large numbers ===\n";
$x = gmp_mul(gmp_pow(2, 50), gmp_init(15));
$y = gmp_mul(gmp_pow(2, 40), gmp_init(21));
$g = gmp_gcd($x, $y);
echo "gcd(2^50 * 15, 2^40 * 21) = " . gmp_strval($g) . "\n";

echo "\n=== GMP: comparison ===\n";
$a = gmp_init("9999999999999999999999");
$b = gmp_init("9999999999999999999998");
echo "a > b: " . (gmp_cmp($a, $b) > 0 ? "yes" : "no") . "\n";
echo "a < b: " . (gmp_cmp($a, $b) < 0 ? "yes" : "no") . "\n";
echo "a == a: " . (gmp_cmp($a, $a) === 0 ? "yes" : "no") . "\n";

echo "\n=== bcmath: fixed-point money math ===\n";
bcscale(2);
$balance = "1000.00";
$txns = ["+250.50", "-75.25", "+10.00", "-300.99", "+999.99"];
echo "starting: $balance\n";
foreach ($txns as $t) {
    $op = $t[0];
    $amt = substr($t, 1);
    $balance = $op === '+' ? bcadd($balance, $amt) : bcsub($balance, $amt);
    echo sprintf("  %s %-6s -> %s\n", $op, $amt, $balance);
}
echo "final: $balance\n";

echo "\n=== bcmath: precise division ===\n";
$cases = [
    [1, 3, 20],
    [22, 7, 30],
    [355, 113, 15],
    [1, 7, 12],
];
foreach ($cases as [$a, $b, $scale]) {
    $r = bcdiv((string)$a, (string)$b, $scale);
    echo "$a / $b (scale $scale) = $r\n";
}

echo "\n=== bcmath: exponents ===\n";
echo "2^64 = " . bcpow("2", "64") . "\n";
echo "1.5^10 (scale 4) = " . bcpow("1.5", "10", 4) . "\n";

echo "\n=== bcmath: comparison drives sort ===\n";
$nums = ["100.5", "100.49", "99.99", "100.50", "100.500", "99.999"];
usort($nums, fn($a, $b) => bccomp($a, $b, 3));
echo implode(", ", $nums) . "\n";

echo "\n=== bridge GMP <-> string for serialization ===\n";
$secret = gmp_pow(gmp_init(7), 50);
$serialized = gmp_strval($secret);
$round_tripped = gmp_init($serialized);
echo "round trip match: " . (gmp_cmp($secret, $round_tripped) === 0 ? "yes" : "no") . "\n";
echo "value: $serialized\n";
