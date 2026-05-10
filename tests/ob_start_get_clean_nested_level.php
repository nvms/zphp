<?php
ob_start();
echo "captured1";
$x = ob_get_clean();
echo "[", $x, "]\n";

ob_start();
echo "captured2";
echo ob_get_contents();
ob_end_clean();
echo "after\n";

ob_start();
echo "out";
$contents = ob_get_contents();
ob_end_clean();
echo "got:", $contents, "\n";

ob_start();
echo "before";
ob_clean();
echo "after";
$x = ob_get_clean();
echo "[", $x, "]\n";

echo ob_get_level(), "\n";
ob_start();
echo ob_get_level(), "\n";
ob_start();
echo ob_get_level(), "\n";
ob_end_clean();
echo ob_get_level(), "\n";
ob_end_clean();
echo ob_get_level(), "\n";

ob_start();
echo "outer-";
ob_start();
echo "inner";
$inner = ob_get_clean();
echo "[$inner]";
echo "-outer";
$outer = ob_get_clean();
echo "got:", $outer, "\n";

ob_start();
echo "abc";
$x = ob_get_contents();
echo " more";
$y = ob_get_clean();
echo "[", $x, "][", $y, "]\n";

ob_start(function ($buf) { return strtoupper($buf); });
echo "hello world";
$x = ob_get_clean();
echo "[", $x, "]\n";

ob_start();
echo "first ";
ob_start();
echo "second ";
ob_start();
echo "third";
$t = ob_get_clean();
echo "<", $t, ">";
$s = ob_get_clean();
echo "<", $s, ">";
$f = ob_get_clean();
echo "got:", $f, "\n";

ob_start();
echo "x";
ob_flush();
$x = ob_get_clean();
echo "[", $x, "]\n";

ob_start();
for ($i = 0; $i < 5; $i++) echo $i;
$out = ob_get_clean();
echo $out, "\n";

ob_start();
printf("%d-%s", 42, "x");
$o = ob_get_clean();
echo $o, "\n";

ob_start();
$arr = [1, 2, 3];
foreach ($arr as $v) echo $v, " ";
$result = ob_get_clean();
echo trim($result), "\n";

ob_start();
echo "level1 ";
ob_start();
echo "level2 ";
echo ob_get_level();
ob_end_clean();
$x = ob_get_clean();
echo "result:[", $x, "]\n";

$captured = "";
ob_start();
echo "loop";
$captured = ob_get_clean();
echo "after:", $captured, "\n";

class Logger {
    public function log(string $msg): void {
        ob_start();
        echo "[$msg]";
        $captured = ob_get_clean();
        echo $captured;
    }
}
(new Logger)->log("test");
echo "\n";

function helper(): string {
    ob_start();
    echo "inner-helper-";
    var_dump(42);
    return ob_get_clean();
}
echo helper(), "\n";

ob_start();
echo "single ";
echo "echo ";
echo "string";
$x = ob_get_clean();
echo $x, "\n";
