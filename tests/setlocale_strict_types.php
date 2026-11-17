<?php
declare(strict_types=1);
// under strict_types setlocale() takes no int for a locale
try {
    setlocale(LC_ALL, 0, "0");
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    setlocale(LC_ALL, "0", 0);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
var_dump(setlocale(LC_ALL, "0"));
