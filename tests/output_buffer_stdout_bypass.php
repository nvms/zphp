<?php
// writes to STDOUT bypass output buffering, inside a handler too
echo "before\n";
ob_start();
echo "buffered\n";
fwrite(STDOUT, "direct 1\n");
$held = ob_get_clean();
fwrite(STDOUT, "direct 2\n");
echo "held: ", $held;

ob_start(function ($text) {
    fwrite(STDOUT, "[handler sees " . strlen($text) . " bytes]\n");
    return strtoupper($text);
});
ob_start();
echo "inner\n";
fwrite(STDOUT, "direct 3\n");
ob_end_flush();
echo "outer\n";
ob_end_flush();

ob_start();
$o = fopen('php://output', 'w');
fwrite($o, "via output\n");
$s = fopen('php://stdout', 'w');
fwrite($s, "via stdout\n");
file_put_contents('php://output', "fpc output\n");
file_put_contents('php://stdout', "fpc stdout\n");
$x = ob_get_clean();
echo "held: [", $x, "]\n";
