<?php
$saved = [];
set_error_handler(function ($severity, $msg) use (&$saved) {
    $saved[] = "$severity:$msg";
});

trigger_error("user notice", E_USER_NOTICE);
trigger_error("user warning", E_USER_WARNING);
trigger_error("user error", E_USER_ERROR);
trigger_error("user deprecated", E_USER_DEPRECATED);

print_r($saved);
restore_error_handler();

$caught = false;
try {
    throw new \RuntimeException("test");
} catch (\Throwable $e) {
    $caught = true;
    echo "caught:", $e->getMessage(), "\n";
}
echo $caught ? "y" : "n", "\n";

$handler_called = false;
set_exception_handler(function (\Throwable $e) use (&$handler_called) {
    $handler_called = true;
    echo "handler:", $e->getMessage(), "\n";
});

restore_exception_handler();
echo "no-handler-yet\n";

echo E_ERROR, " ", E_WARNING, " ", E_NOTICE, " ", E_USER_ERROR, " ", E_USER_WARNING, " ", E_USER_NOTICE, " ", E_USER_DEPRECATED, "\n";
echo E_DEPRECATED, " ", E_RECOVERABLE_ERROR, "\n";

echo error_reporting(0), "\n";
echo error_reporting(), "\n";
error_reporting(E_ALL);
echo error_reporting(), "\n";

echo defined("E_ALL") ? "y" : "n", "\n";
echo defined("E_USER_ERROR") ? "y" : "n", "\n";
echo defined("E_USER_WARNING") ? "y" : "n", "\n";

class MyException extends \RuntimeException {
    public function __construct(public string $detail, string $msg = "") {
        parent::__construct($msg);
    }
}

try {
    throw new MyException("info", "oops");
} catch (\Exception $e) {
    if ($e instanceof MyException) echo $e->detail, "|", $e->getMessage(), "\n";
}

try {
    throw new \LogicException("logic1");
} catch (\LogicException $e) {
    try {
        throw new \RuntimeException("inner", 0, $e);
    } catch (\RuntimeException $r) {
        echo $r->getMessage(), "\n";
        echo $r->getPrevious()->getMessage(), "\n";
    }
}

echo error_get_last() === null ? "null" : "x", "\n";

$saved2 = [];
set_error_handler(function ($sev, $msg, $file, $line) use (&$saved2) {
    $saved2[] = compact("sev", "msg");
});

trigger_error("a", E_USER_NOTICE);
trigger_error("b", E_USER_WARNING);
trigger_error("c", E_USER_NOTICE);
restore_error_handler();

print_r($saved2);

assert(true);
echo "after-true\n";

assert(1 + 1 === 2);
echo "after-eq\n";

$x = 10;
assert($x > 0);
echo "after-x\n";

try {
    $r = new \LogicException("from-try");
    throw $r;
} catch (\Throwable $t) {
    echo "got:", $t->getMessage(), "\n";
    echo $t->getFile() !== "" ? "f" : "x", "\n";
    echo is_int($t->getLine()) ? "i" : "x", "\n";
}

function safeDiv(int $a, int $b): int {
    if ($b === 0) throw new \DivisionByZeroError("div");
    return intdiv($a, $b);
}

try {
    safeDiv(10, 0);
} catch (\DivisionByZeroError $e) {
    echo "dbz:", $e->getMessage(), "\n";
}

echo function_exists("trigger_error") ? "y" : "n", "\n";
echo function_exists("set_error_handler") ? "y" : "n", "\n";
echo function_exists("set_exception_handler") ? "y" : "n", "\n";
echo function_exists("restore_error_handler") ? "y" : "n", "\n";
echo function_exists("error_reporting") ? "y" : "n", "\n";
echo function_exists("error_get_last") ? "y" : "n", "\n";

$set = E_ERROR | E_WARNING;
$has_err = ($set & E_ERROR) !== 0;
$has_warn = ($set & E_WARNING) !== 0;
$has_notice = ($set & E_NOTICE) !== 0;
echo $has_err ? "y" : "n", " ", $has_warn ? "y" : "n", " ", $has_notice ? "y" : "n", "\n";

$mask = E_ALL & ~E_NOTICE;
echo ($mask & E_NOTICE) === 0 ? "y" : "n", "\n";
echo ($mask & E_ERROR) !== 0 ? "y" : "n", "\n";

class CustomErr extends \Error {
    public string $errCode;
    public function __construct(string $c, string $msg) {
        parent::__construct($msg);
        $this->errCode = $c;
    }
}

try {
    throw new CustomErr("E001", "bad");
} catch (\Error $e) {
    if ($e instanceof CustomErr) echo $e->errCode, "/", $e->getMessage(), "\n";
}

$msg_received = "";
set_error_handler(function ($sev, $msg) use (&$msg_received) {
    $msg_received = $msg;
    return true;
});
trigger_error("captured", E_USER_NOTICE);
echo $msg_received, "\n";
restore_error_handler();
