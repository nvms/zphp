<?php
// imagecreate() and imagecreatetruecolor() refuse a size gd can't allocate
foreach (['imagecreate', 'imagecreatetruecolor'] as $f) {
    foreach ([[0, 5], [5, 0], [-3, 2], [2, -3], [PHP_INT_MAX, 1]] as [$w, $h]) {
        try {
            $f($w, $h);
            echo "created\n";
        } catch (ValueError $e) {
            echo $e->getMessage(), "\n";
        }
    }
    $im = $f(3, 2);
    var_dump(imagesx($im), imagesy($im));
}
