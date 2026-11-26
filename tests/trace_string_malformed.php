<?php
// getTraceAsString() over a trace that isn't what the engine made
// (zend_trace_to_string and _build_trace_string)
set_error_handler(function ($no, $msg) { echo "warning: $msg\n"; return true; });
$e = new Exception();
$ref = new ReflectionProperty($e, 'trace');
$traces = [
    [null],
    [[]],
    [['file' => null, 'line' => null, 'class' => null, 'type' => null, 'function' => null, 'args' => null]],
    [['file' => 'a.php', 'line' => '12', 'function' => 'f']],
    [['file' => 'a.php', 'function' => 'f', 'args' => [1, [1], null, true, 1.5]]],
    [['line' => 3, 'function' => 'g']],
    [5, ['function' => 'h'], 'x' => ['function' => 'i', 'class' => 'C', 'type' => '::']],
    [['file' => '', 'line' => 0, 'function' => 'j']],
    [],
];
foreach ($traces as $trace) {
    $ref->setValue($e, $trace);
    var_dump($e->getTraceAsString());
}

// what converting an uncaught throwable throws names no file: the script
// has stopped
class BadMessage extends Exception {
    public function __construct() {
        $this->message = new stdClass;
    }
}
ini_set('display_errors', '1');
ini_set('log_errors', '0');
throw new BadMessage;
