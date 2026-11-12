<?php
// a replacement callback that throws fails its subject; the remaining
// subjects are still converted (with their warnings) before the exception
// leaves the call, and the callback isn't called again
$calls = 0;
$cb = function ($m) use (&$calls) {
    $calls++;
    throw new Exception("boo $calls");
};
foreach ([['ab', 'cd', ['x'], 'ef'], 'ab'] as $subject) {
    try {
        var_dump(preg_replace_callback('/\w/', $cb, $subject, -1, $count));
    } catch (Exception $e) {
        echo $e->getMessage(), " calls=$calls count=", var_export($count ?? null, true), " ", preg_last_error(), "\n";
    }
}
try {
    var_dump(preg_replace_callback_array(['/a/' => $cb, '/b/' => fn($m) => 'B'], ['ab', 'ba']));
} catch (Exception $e) {
    echo $e->getMessage(), " calls=$calls\n";
}
var_dump(preg_replace_callback('/\w/', fn($m) => new ArrayObject([]) instanceof Countable ? 'ok' : 'no', 'ab'));
