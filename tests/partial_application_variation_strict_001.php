<?php
declare(strict_types=1);

function foo(int $int) {
    var_dump($int);
}

$foo = foo(?);

try {
    $foo("42");
} catch (TypeError $ex) {
    printf("%s: %s\n", $ex::class, $ex->getMessage());
}
?>
