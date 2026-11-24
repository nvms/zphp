<?php
// PDO::ATTR_ORACLE_NULLS takes only the PDO::NULL_* modes; another value is
// a ValueError and leaves the attribute as it was
$pdo = new PDO('sqlite::memory:');
foreach ([PDO::NULL_NATURAL, PDO::NULL_EMPTY_STRING, PDO::NULL_TO_STRING] as $value) {
    echo "valid mode: ";
    var_dump($pdo->setAttribute(PDO::ATTR_ORACLE_NULLS, $value));
    var_dump($pdo->getAttribute(PDO::ATTR_ORACLE_NULLS));
}
foreach ([-1, 3, 4, PHP_INT_MAX, PHP_INT_MIN] as $value) {
    try {
        $pdo->setAttribute(PDO::ATTR_ORACLE_NULLS, $value);
    } catch (ValueError $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
    echo "unchanged mode: ";
    var_dump($pdo->getAttribute(PDO::ATTR_ORACLE_NULLS));
}
