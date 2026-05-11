<?php
// covers: arbitrary-precision integer math via libgmp

$a = gmp_init('12345678901234567890');
$b = gmp_init('98765432109876543210');
echo "a = ", gmp_strval($a), "\n";
echo "b = ", gmp_strval($b), "\n";
echo "a + b = ", gmp_strval(gmp_add($a, $b)), "\n";
echo "b - a = ", gmp_strval(gmp_sub($b, $a)), "\n";
echo "a * b = ", gmp_strval(gmp_mul($a, $b)), "\n";
echo "b / a = ", gmp_strval(gmp_div_q($b, $a)), "\n";
echo "b mod a = ", gmp_strval(gmp_mod($b, $a)), "\n";

echo "cmp(a,b) = ", gmp_cmp($a, $b), "\n";
echo "sign(neg) = ", gmp_sign(gmp_init('-5')), "\n";

// pow + powm
echo "2^100 = ", gmp_strval(gmp_pow(2, 100)), "\n";
echo "2^100 mod 1000003 = ", gmp_strval(gmp_powm(2, 100, 1000003)), "\n";

// gcd / lcm
echo "gcd(48,36) = ", gmp_strval(gmp_gcd(48, 36)), "\n";
echo "lcm(4,6) = ", gmp_strval(gmp_lcm(4, 6)), "\n";

// bit ops
echo "5 & 3 = ", gmp_strval(gmp_and(5, 3)), "\n";
echo "5 | 3 = ", gmp_strval(gmp_or(5, 3)), "\n";
echo "5 ^ 3 = ", gmp_strval(gmp_xor(5, 3)), "\n";
echo "popcount(255) = ", gmp_popcount(255), "\n";
echo "testbit(5,0) = ", gmp_testbit(5, 0) ? 1 : 0, "\n";
echo "testbit(5,1) = ", gmp_testbit(5, 1) ? 1 : 0, "\n";

// sqrt
echo "sqrt(144) = ", gmp_strval(gmp_sqrt(144)), "\n";
echo "perfect_square(144) = ", gmp_perfect_square(144) ? 1 : 0, "\n";
echo "perfect_square(145) = ", gmp_perfect_square(145) ? 1 : 0, "\n";

// prime
echo "prob_prime(17) = ", gmp_prob_prime(17), "\n";
echo "prob_prime(15) = ", gmp_prob_prime(15), "\n";
echo "nextprime(10) = ", gmp_strval(gmp_nextprime(10)), "\n";

// invert
echo "invert(3, 7) = ", gmp_strval(gmp_invert(3, 7)), "\n";

// hamdist
echo "hamdist(0b1100, 0b1010) = ", gmp_hamdist(12, 10), "\n";

// __toString via cast
$x = gmp_init('999999999999999999999');
echo "cast = ", (string)$x, "\n";

// factorial-ish: 50! exceeds 64-bit
$f = gmp_init(1);
for ($i = 2; $i <= 30; $i++) $f = gmp_mul($f, gmp_init($i));
echo "30! = ", gmp_strval($f), "\n";
