<?php
class NativeOutputBox {
    public private(set) mixed $output = 41;
    public private(set) array $items = [41];
    function legal() { preg_match('/a/', 'a', $this->output); }
}
$b = new NativeOutputBox;
$callbacks = 0;
function outputAttempt($f) {
    try { $f(); echo "unexpected success\n"; }
    catch (Error $e) { echo $e->getMessage(), "\n"; }
}
outputAttempt(function () use ($b) { preg_match('/a/', 'a', $b->output); });
outputAttempt(function () use ($b) { $f = 'preg_match_all'; $f('/a/', 'a', $b->output); });
outputAttempt(function () use ($b) { preg_replace('/a/', 'b', 'a', -1, $b->output); });
outputAttempt(function () use ($b) {
    preg_replace_callback('/a/', function ($m) { global $callbacks; ++$callbacks; return 'b'; }, 'a', -1, $b->output);
});
outputAttempt(function () use ($b) { str_replace('a', 'b', 'a', $b->items[0]); });
outputAttempt(function () use ($b) { parse_str('a=1', $b->output); });
outputAttempt(function () use ($b) { sscanf('7', '%d', $b->output); });
outputAttempt(function () use ($b) { similar_text('a', 'a', $b->output); });
outputAttempt(function () use ($b) { is_callable('strlen', false, $b->output); });
echo "callbacks=$callbacks\n";
var_dump($b->output, $b->items);
$b->legal();
var_dump($b->output);
