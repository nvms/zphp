<?php
// php code re-entered from natives without end runs out of native stack;
// php throws an Error instead of crashing (zend.max_allowed_stack_size).
// the size in the message depends on the thread's stack, so it is masked

// which frame of a repeating cycle meets the limit depends on how much
// native stack each frame takes, so only the cycle's presence is checked
function report(Throwable $e, string $recursing)
{
    echo get_class($e), ": ", preg_replace('/of \d+ bytes/', 'of N bytes', $e->getMessage()), "\n";
    $names = array_map(fn($f) => ($f['class'] ?? '') . ($f['type'] ?? '') . $f['function'], $e->getTrace());
    echo "  in the trace: ", var_export(in_array($recursing, $names, true), true), "\n";
}

function viaCallback($n)
{
    return array_map(fn($x) => viaCallback($n + 1), [1]);
}

try {
    viaCallback(0);
} catch (Error $e) {
    report($e, 'viaCallback');
}

class Chain
{
    public function __get($name)
    {
        $next = $name . "x";
        return $this->$next;
    }
}

try {
    (new Chain())->a;
} catch (Error $e) {
    report($e, 'Chain->__get');
}

function viaSort($n)
{
    $a = [2, 1];
    // (php reports a closure with use() at its declaration line, zphp at its
    // first statement: keep them on one line)
    usort($a, function ($x, $y) use ($n) { viaSort($n + 1); return $x <=> $y; });
}

try {
    viaSort(0);
} catch (Error $e) {
    report($e, 'viaSort');
}

class Stringy
{
    public function __toString(): string
    {
        return "<" . new Stringy() . ">";
    }
}

try {
    echo new Stringy();
} catch (Error $e) {
    report($e, 'Stringy->__toString');
}

// the script carries on normally afterwards
echo implode(",", array_map(fn($x) => $x * 2, [1, 2, 3])), "\n";
