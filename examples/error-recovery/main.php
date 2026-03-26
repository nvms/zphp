<?php
// covers: set_error_handler, set_exception_handler, trigger_error,
//   error_reporting, restore_error_handler, ob_start, ob_get_clean,
//   try/catch with custom handlers, E_USER_ERROR/E_USER_WARNING/E_USER_NOTICE

// --- custom error handler ---
echo "=== error handler ===\n";
$errors = [];
set_error_handler(function($errno, $errstr, $errfile, $errline) use (&$errors) {
    $errors[] = ['level' => $errno, 'message' => $errstr];
    return true;
});

trigger_error("test warning", E_USER_WARNING);
trigger_error("test notice", E_USER_NOTICE);

echo "captured errors: " . count($errors) . "\n";
echo "first: {$errors[0]['message']}\n";
echo "second: {$errors[1]['message']}\n";

restore_error_handler();

// --- custom exception handler ---
echo "\n=== exception handler ===\n";
$caught_ex = null;
set_exception_handler(function($e) use (&$caught_ex) {
    $caught_ex = $e->getMessage();
});

// exception handler is for uncaught exceptions, test via try/catch instead
try {
    throw new RuntimeException("planned failure");
} catch (RuntimeException $e) {
    echo "caught: " . $e->getMessage() . "\n";
}

// --- nested try/catch with error handler ---
echo "\n=== nested recovery ===\n";
$log = [];
set_error_handler(function($errno, $errstr) use (&$log) {
    $log[] = "error: $errstr";
    return true;
});

function riskyOperation($depth) {
    if ($depth <= 0) {
        trigger_error("max depth reached", E_USER_WARNING);
        return "fallback";
    }
    try {
        if ($depth == 2) {
            throw new InvalidArgumentException("bad depth: $depth");
        }
        return "ok at depth $depth";
    } catch (InvalidArgumentException $e) {
        trigger_error($e->getMessage(), E_USER_NOTICE);
        return riskyOperation($depth - 1);
    }
}

echo riskyOperation(3) . "\n";
echo riskyOperation(2) . "\n";
echo "log entries: " . count($log) . "\n";
foreach ($log as $entry) {
    echo "  $entry\n";
}

restore_error_handler();

// --- error reporting level ---
echo "\n=== error reporting ===\n";
$level = error_reporting();
echo "reporting is int: " . (is_int($level) ? 'yes' : 'no') . "\n";

// --- output buffering with error recovery ---
echo "\n=== output buffering ===\n";
ob_start();
echo "buffered content";
try {
    throw new Exception("mid-buffer error");
} catch (Exception $e) {
    echo " [recovered]";
}
$output = ob_get_clean();
echo "captured: $output\n";

// nested output buffering
ob_start();
echo "outer";
ob_start();
echo " inner";
$inner = ob_get_clean();
echo " middle";
$outer = ob_get_clean();
echo "outer: $outer\n";
echo "inner: $inner\n";

// --- exception chaining ---
echo "\n=== exception chaining ===\n";
try {
    try {
        throw new RuntimeException("root cause");
    } catch (RuntimeException $e) {
        throw new LogicException("wrapper: " . $e->getMessage(), 0, $e);
    }
} catch (LogicException $e) {
    echo "caught: " . $e->getMessage() . "\n";
    $prev = $e->getPrevious();
    echo "previous: " . ($prev ? $prev->getMessage() : 'none') . "\n";
}

// --- finally with return ---
echo "\n=== finally ===\n";
function withFinally($fail) {
    $result = "start";
    try {
        if ($fail) throw new Exception("boom");
        $result .= " success";
    } catch (Exception $e) {
        $result .= " caught";
    } finally {
        $result .= " finally";
    }
    return $result;
}

echo withFinally(false) . "\n";
echo withFinally(true) . "\n";

echo "\ndone\n";
