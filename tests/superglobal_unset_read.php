<?php
// reading a superglobal that was unset (or $_SESSION before a session starts)
// warns as an undefined global
unset($_SERVER);
var_dump($_SERVER);
function f() {
    unset($_GET);
    var_dump($_GET);
    var_dump(isset($_POST));
}
f();
var_dump($_GET);
$_ENV = 5;
var_dump($_ENV);
unset($_COOKIE['x']);
var_dump($_SESSION ?? "none", isset($_SERVER));
var_dump($_SESSION);
