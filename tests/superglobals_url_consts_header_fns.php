<?php
echo PHP_URL_SCHEME, " ", PHP_URL_HOST, " ", PHP_URL_PATH, "\n";

$env = $_ENV;
echo is_array($env) ? "y" : "n", "\n";

$server = $_SERVER;
echo is_array($server) ? "y" : "n", "\n";

$_REQUEST["x"] = 1;
echo isset($_REQUEST["x"]) ? "y" : "n", "\n";

echo gettype($_GET), " ", gettype($_POST), " ", gettype($_COOKIE), "\n";

$_GET["a"] = 1;
$_GET["b"] = 2;
echo count($_GET), "\n";

$origin = $_SERVER ?? [];
echo gettype($origin), "\n";

echo function_exists("header") ? "y" : "n", "\n";
echo function_exists("setcookie") ? "y" : "n", "\n";
echo function_exists("headers_sent") ? "y" : "n", "\n";
echo function_exists("http_response_code") ? "y" : "n", "\n";
echo function_exists("headers_list") ? "y" : "n", "\n";
echo function_exists("header_remove") ? "y" : "n", "\n";
