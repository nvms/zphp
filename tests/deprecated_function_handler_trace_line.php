<?php
// the deprecation of a #[\Deprecated] function is raised before its frame
// exists: the error handler is called from the line of the call

#[Deprecated]
function foo(string $v) {
    return $v . '!';
}

class C {
    #[Deprecated("use other()")]
    public function m() {
        return 1;
    }
}

function frames(array $trace) {
    foreach ($trace as $i => $f) {
        echo "  #$i ", str_starts_with($f['function'], '{closure') ? '{closure}' : $f['function'], " line ", $f['line'] ?? '-', "\n";
    }
}

set_error_handler(function ($number, $message) {
    throw new Exception($message);
});

try {
    $a = foo('x');
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
    frames($e->getTrace());
}

function outer() {
    return (new C)->m();
}

try {
    outer();
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
    frames($e->getTrace());
}

set_error_handler(function ($number, $message) {
    echo $message, "\n";
    frames(debug_backtrace());
    return true;
});
foo('y');
outer();
