<?php
// regression: when a native function (PDO::prepare) throws via
// throwBuiltinException and a user try/catch is in scope, the catch
// handler must run instead of zphp surfacing 'internal RuntimeError'
$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
try {
    $pdo->prepare('THIS IS NOT VALID SQL FROM A FUNCTION');
    echo "no exception\n";
} catch (PDOException $e) {
    echo "caught: ", get_class($e), "\n";
}
echo "done\n";
