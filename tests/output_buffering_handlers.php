<?php
error_reporting(0);

ob_start();
echo "captured";
$c = ob_get_contents();
ob_end_clean();
echo "[$c]\n";

ob_start();
echo "first";
echo " ";
echo "second";
echo ob_get_length(), "\n";
$out = ob_get_clean();
echo "[$out]\n";

ob_start();
echo "outer ";
ob_start();
echo "inner";
$inner = ob_get_clean();
echo "[$inner] ";
$outer = ob_get_clean();
echo "[$outer]\n";

echo ob_get_level(), "\n";
ob_start();
echo ob_get_level(), "\n";
ob_start();
echo ob_get_level(), "\n";
ob_end_clean();
echo ob_get_level(), "\n";
ob_end_clean();

ob_start(function ($buf) {
    return strtoupper($buf);
});
echo "transform me";
$res = ob_get_clean();
echo $res, "\n";

ob_start();
echo "hidden";
ob_clean();
echo "visible";
$res = ob_get_clean();
echo "[$res]\n";

ob_start();
echo "a";
ob_start();
echo "b";
ob_end_flush();
$res = ob_get_clean();
echo "[$res]\n";

ob_start();
echo "x", "y", "z";
$res = ob_get_clean();
echo strlen($res), "\n";

ob_start();
ob_start();
ob_start();
echo ob_get_level(), "\n";
ob_end_clean();
ob_end_clean();
ob_end_clean();
echo ob_get_level(), "\n";

ob_start();
for ($i = 0; $i < 5; $i++) echo $i;
echo "\nLEN: ", ob_get_length();
$out = ob_get_clean();
echo "\n[$out]\n";

$res = ob_start(function ($s) {
    return "<wrapped>" . $s . "</wrapped>";
});
echo "content";
$out = ob_get_clean();
echo $out, "\n";

ob_start();
echo "no flush";
ob_clean();
echo " new content";
$out = ob_get_clean();
echo "[$out]\n";

$handlers = ob_list_handlers();
print_r($handlers);

$ok = ob_start("foo_handler_does_not_exist");
echo $ok === false ? "false" : "true", "\n";
print_r(ob_list_handlers());

ob_start("strtoupper");
print_r(ob_list_handlers());
ob_end_clean();
