<?php
// debug_backtrace() entries in zend_fetch_debug_backtrace's key order, with
// a method's $this under DEBUG_BACKTRACE_PROVIDE_OBJECT (the default), also
// for an internal method that calls back

function keys(array $trace): void
{
    foreach ($trace as $e) {
        $shown = [];
        foreach ($e as $k => $v) {
            if ($k === 'function' && str_starts_with($v, '{closure')) $v = '{closure}';
            $shown[] = $k . ($k === 'object' ? '=' . get_class($v) : ($k === 'function' || $k === 'class' ? '=' . $v : ''));
        }
        echo implode(" ", $shown), "\n";
    }
    echo "--\n";
}

class A
{
    public function m() { keys(debug_backtrace()); }
    public static function s() { keys(debug_backtrace()); }
    public function quiet() { keys(debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS)); }
    public function noObject() { keys(debug_backtrace(0 | DEBUG_BACKTRACE_IGNORE_ARGS | 0, 1)); }
}

function f() { (new A)->m(); }
f();
A::s();
(new A)->quiet();
(new A)->noObject();

$o = new ArrayObject([3, 1]);
$o->uksort(function ($a, $b) {
    static $once = false;
    if (!$once) {
        $once = true;
        $trace = debug_backtrace();
        // php's ArrayObject sorts by calling the array function itself
        $trace = array_values(array_filter($trace, fn($e) => !(isset($e['function']) && $e['function'] === 'uksort' && !isset($e['class']))));
        keys($trace);
    }
    return $a <=> $b;
});

$c = function () { keys(debug_backtrace()); };
$c();
$bound = Closure::bind(function () { keys(debug_backtrace()); }, new A, A::class);
$bound();
