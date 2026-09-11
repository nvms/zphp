<?php
// covers: GdImage and GMP keep working when a script overwrites the property names that once held their C pointers, clone semantics per class

$im = imagecreatetruecolor(12, 7);
try {
    $im->__gd_ptr = 0x41414141;
} catch (Error $e) {
}
var_dump(imagesx($im), imagesy($im));
try {
    $copy = clone $im;
    echo "cloned\n";
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
imagedestroy($im);

$n = gmp_init("123456789012345678901234567890");
$n->__mpz = 0x41414141;
var_dump(gmp_strval($n));
var_dump(isset($n->__mpz));
$m = clone $n;
$m = gmp_add($m, 1);
var_dump(gmp_strval($n), gmp_strval($m));
$k = clone $n;
var_dump(gmp_cmp($k, $n) === 0);
var_dump($k !== $n);
