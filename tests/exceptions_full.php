<?php
// basic Exception
try { throw new Exception("oops"); }
catch (Exception $e) { echo $e->getMessage(), "\n"; }

// code
try { throw new Exception("err", 42); }
catch (Exception $e) { echo $e->getCode(), "\n"; }

// chained
try {
    try {
        throw new Exception("inner", 1);
    } catch (Exception $e) {
        throw new Exception("outer", 2, $e);
    }
} catch (Exception $e) {
    echo $e->getMessage(), "/", $e->getCode(), "\n";
    $prev = $e->getPrevious();
    echo $prev->getMessage(), "/", $prev->getCode(), "\n";
}

// custom class
class MyException extends Exception {
    public function __construct(string $msg, public readonly string $tag = "") {
        parent::__construct($msg);
    }
}
try { throw new MyException("custom", "X"); }
catch (MyException $e) { echo $e->getMessage(), "/", $e->tag, "\n"; }

// catch parent type
try { throw new MyException("from-my"); }
catch (Exception $e) { echo "as-Ex:", $e->getMessage(), "\n"; }

// multi-catch
try { throw new RuntimeException("rt"); }
catch (LogicException | RuntimeException $e) { echo get_class($e), "\n"; }

// catch order: more-specific must precede less-specific (PHP just uses first match)
try { throw new RuntimeException("test"); }
catch (Exception $e) { echo "Ex:", $e->getMessage(), "\n"; }

// Error vs Exception
try { throw new TypeError("type-err"); }
catch (Error $e) { echo "Err:", $e->getMessage(), "\n"; }

try { throw new ValueError("val-err"); }
catch (ValueError $e) { echo $e->getMessage(), "\n"; }

try { throw new ValueError("val-err"); }
catch (Error $e) { echo "as-Err:", $e->getMessage(), "\n"; }

try { throw new ValueError("val-err"); }
catch (Throwable $e) { echo "Throw:", get_class($e), "\n"; }

// Throwable catches both
try { throw new Exception("ex"); }
catch (Throwable $e) { echo "Throw-Ex:", get_class($e), "\n"; }

try { throw new Error("er"); }
catch (Throwable $e) { echo "Throw-Er:", get_class($e), "\n"; }

// Throwable instanceof
$e = new Exception("test");
var_dump($e instanceof Throwable);
var_dump($e instanceof Exception);
var_dump($e instanceof Error);

// instanceof Stringable
var_dump($e instanceof Stringable);

// __toString
$e = new Exception("hello", 42);
$s = (string)$e;
echo strpos($s, "Exception") !== false ? "has-class " : "no-class ";
echo strpos($s, "hello") !== false ? "has-msg " : "no-msg ";
echo "\n";

// custom __toString
class MyEx extends Exception {
    public function __toString(): string {
        return "MyEx[" . $this->getMessage() . "]";
    }
}
echo (string)new MyEx("foo"), "\n";

// getFile / getLine
$line = 0;
try {
    $line = __LINE__ + 1;
    throw new Exception("here");
} catch (Exception $e) {
    echo basename($e->getFile()), ":", ($e->getLine() === $line ? "line-match" : "line-mismatch:" . $e->getLine() . "/" . $line), "\n";
}

// SPL exceptions
$exc_types = [
    "InvalidArgumentException",
    "OutOfBoundsException",
    "OutOfRangeException",
    "OverflowException",
    "RangeException",
    "RuntimeException",
    "UnexpectedValueException",
    "LogicException",
    "DomainException",
    "LengthException",
];
foreach ($exc_types as $t) {
    try { throw new $t("x"); }
    catch (\Exception $e) { echo $t, ":", get_class($e) === $t ? "ok " : "no "; }
}
echo "\n";

// catch chain with finally
function chained(): string {
    $log = "";
    try {
        try {
            throw new RuntimeException("inner");
        } finally {
            $log .= "f1 ";
        }
    } catch (Exception $e) {
        $log .= "c " . $e->getMessage() . " ";
    } finally {
        $log .= "f2";
    }
    return $log;
}
echo chained(), "\n";

// re-throw preserves message and code
try {
    try { throw new Exception("r1", 7); }
    catch (Exception $e) { throw $e; }
} catch (Exception $e) {
    echo $e->getMessage(), "/", $e->getCode(), "\n";
}

// instance check getMessage on TypeError, ValueError
$t = new TypeError("t-msg");
echo $t->getMessage(), "\n";

// uncaught throws within native call propagates
class C {
    public function bad(): int { throw new RuntimeException("from-method"); }
}
try { (new C)->bad(); echo "no\n"; }
catch (\RuntimeException $e) { echo "caught:", $e->getMessage(), "\n"; }

// finally returns last expression doesn't matter
function f(): string {
    try {
        return "try";
    } finally {
        // finally runs, doesn't affect return
        $x = "final";
    }
}
echo f(), "\n";

// finally with exception still runs
function g(): string {
    $log = "";
    try {
        throw new Exception("a");
    } catch (Exception $e) {
        $log .= "c";
    } finally {
        $log .= "f";
    }
    return $log;
}
echo g(), "\n";

// nested try/catch
function deep() {
    try {
        try {
            try {
                throw new Exception("deep");
            } catch (LogicException $e) {
                return "logic";
            }
        } catch (RuntimeException $e) {
            return "runtime";
        }
    } catch (Exception $e) {
        return "general:" . $e->getMessage();
    }
}
echo deep(), "\n";

// exception in __construct
class FailCtor {
    public function __construct() {
        throw new Exception("fail-ctor");
    }
}
try { new FailCtor; echo "no\n"; }
catch (Exception $e) { echo "ctor:", $e->getMessage(), "\n"; }

// catch by partial match
try { throw new \LogicException("le"); }
catch (\Throwable $t) { echo get_class($t), "\n"; }

// throw expression
function maybe(?int $x): int {
    return $x ?? throw new InvalidArgumentException("null x");
}
try { echo maybe(null), "\n"; }
catch (InvalidArgumentException $e) { echo "ia:", $e->getMessage(), "\n"; }

// getTrace returns array
try { throw new Exception("trace"); }
catch (Exception $e) {
    $t = $e->getTrace();
    echo gettype($t), "\n";
}

// getTraceAsString returns string
try { throw new Exception("trace2"); }
catch (Exception $e) {
    $s = $e->getTraceAsString();
    echo gettype($s), "\n";
}
