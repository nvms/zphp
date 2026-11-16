<?php
// a stream wrapper's constructor runs with no arguments; one that needs some
// throws an ArgumentCountError that names no calling file and line

class NeedsArg {
    public $context;
    public function __construct($required) {}
    public function stream_open($path, $mode, $options, &$opened) { return true; }
}

stream_wrapper_register('needs', 'NeedsArg');
foreach ([fn() => fopen('needs://x', 'r'), fn() => file_get_contents('needs://x')] as $f) {
    try {
        $f();
    } catch (ArgumentCountError $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
        foreach (array_slice($e->getTrace(), 0, 2) as $frame) echo $frame['function'], ' ';
        echo "\n";
    }
}
