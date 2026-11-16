<?php
// settype() to array or object warns about a NAN, then wraps the variable as
// the warning's handler left it

$replacement = null;
set_error_handler(function ($errno, $errstr) {
    global $nan, $replacement;
    $nan = $replacement;
    echo $errstr, "\n";
});

foreach ([null, 'text', 42, [1, 2]] as $replacement) {
    $nan = fdiv(0, 0);
    settype($nan, 'array');
    var_dump($nan);
    $nan = fdiv(0, 0);
    settype($nan, 'object');
    var_dump($nan);
}

restore_error_handler();
set_error_handler(function ($errno, $errstr) {
    echo $errstr, "\n";
});
$nan = fdiv(0, 0);
settype($nan, 'array');
var_dump($nan);
$nan = fdiv(0, 0);
settype($nan, 'object');
var_dump($nan);
