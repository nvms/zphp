<?php
// covers: arbitrary-precision decimal math via bcmath

echo bcadd('1.234', '2.5', 3), "\n";           // 3.734
echo bcadd('1', '2'), "\n";                    // 3 (scale=0)
echo bcadd('-1.5', '3.5', 2), "\n";            // 2.00
echo bcadd('1.999999999', '0.000000001', 9), "\n"; // 2.000000000

echo bcsub('5', '3', 0), "\n";                 // 2
echo bcsub('1', '0.1', 1), "\n";               // 0.9
echo bcsub('-1', '-1', 0), "\n";               // 0

echo bcmul('3', '4'), "\n";                    // 12
echo bcmul('1.5', '2', 2), "\n";               // 3.00
echo bcmul('0.1', '0.1', 4), "\n";             // 0.0100
echo bcmul('123456789', '987654321'), "\n";    // 121932631112635269

echo bcdiv('10', '3', 4), "\n";                // 3.3333
try { bcdiv('1', '0', 5); echo "no throw\n"; } catch (DivisionByZeroError $e) { echo "div0: ", $e->getMessage(), "\n"; }
echo bcdiv('100', '4', 0), "\n";               // 25
echo bcdiv('-7', '2', 2), "\n";                // -3.50

echo bcmod('10', '3'), "\n";                   // 1
echo bcmod('17', '5'), "\n";                   // 2
echo bcmod('-10', '3'), "\n";                  // -1 (PHP behavior)

echo bcpow('2', '10'), "\n";                   // 1024
echo bcpow('2', '20'), "\n";                   // 1048576
echo bcpow('3', '5', 0), "\n";                 // 243

echo bcsqrt('2', 10), "\n";                    // 1.4142135623
echo bcsqrt('25', 0), "\n";                    // 5
echo bcsqrt('0', 4), "\n";                     // 0.0000

echo bccomp('1', '2'), "\n";                   // -1
echo bccomp('5', '5'), "\n";                   // 0
echo bccomp('10', '2'), "\n";                  // 1
echo bccomp('1.0001', '1', 2), "\n";           // 0 (compared at scale=2)
echo bccomp('1.0001', '1', 4), "\n";           // 1

echo bcscale(4), "\n";                         // 0 (previous)
echo bcadd('1.1', '2.2'), "\n";                // 3.3000
echo bcscale(), "\n";                          // 4

// stress: factorial via bcmul
$f = '1';
for ($i = 2; $i <= 20; $i++) {
    $f = bcmul($f, (string)$i);
}
echo "20! = $f\n";
