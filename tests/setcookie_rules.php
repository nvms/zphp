<?php
// setcookie and setrawcookie check their name, value and options as
// php_setcookie does, and build the header with php's attribute names
ob_start();
$calls = [
    fn() => setcookie(""),
    fn() => setcookie("a=b"),
    fn() => setcookie("a b"),
    fn() => setrawcookie("a", "b c"),
    fn() => setcookie("a", "b c"),
    fn() => setcookie("a", "b", ["path" => "/a;b"]),
    fn() => setcookie("a", "b", ["domain" => "a,b"]),
    fn() => setcookie("a", "b", ["expires" => 253402300800]),
    fn() => setcookie("a", "b", ["partitioned" => true]),
    fn() => setcookie("a", "b", ["bogus" => 1]),
    fn() => setcookie("a", "b", [0 => 1]),
    fn() => setcookie("a", "b", ["path" => "/"], "/x"),
    fn() => setcookie("a", "b", 0, "/a b"),
    fn() => setcookie("name", "va lue+ü", ["path" => "/p", "domain" => "example.com", "secure" => true, "httponly" => true, "samesite" => "Strict", "partitioned" => true]),
    fn() => setrawcookie("name", "raw%20value", 0, "/p", "example.com", true, true),
    fn() => setcookie("deleted", ""),
    fn() => setcookie("deleted2"),
];
foreach ($calls as $i => $call) {
    try {
        var_dump($call());
    } catch (Throwable $e) {
        echo $i, " ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}
$out = ob_get_clean();
echo $out;
