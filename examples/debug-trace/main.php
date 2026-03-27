<?php
// covers: debug_backtrace, debug_print_backtrace, stack frame inspection,
//   class method traces, nested call chains, backtrace limit, ignore args option

function add($a, $b) {
    $trace = debug_backtrace();
    return ['result' => $a + $b, 'trace' => $trace];
}

function calculate($x, $y) {
    return add($x * 2, $y * 3);
}

function run() {
    return calculate(5, 10);
}

// basic trace through nested calls
$data = run();
$trace = $data['trace'];

echo "=== basic backtrace ===\n";
echo "frames: " . count($trace) . "\n";
echo "frame 0 function: " . $trace[0]['function'] . "\n";
echo "frame 1 function: " . $trace[1]['function'] . "\n";
echo "frame 2 function: " . $trace[2]['function'] . "\n";
echo "has file: " . (isset($trace[0]['file']) ? 'yes' : 'no') . "\n";
echo "has line: " . (isset($trace[0]['line']) ? 'yes' : 'no') . "\n";

// class method traces
class Logger {
    public function log($msg) {
        return debug_backtrace();
    }

    public function info($msg) {
        return $this->log("[INFO] $msg");
    }
}

class App {
    private $logger;

    public function __construct() {
        $this->logger = new Logger();
    }

    public function handle($request) {
        return $this->logger->info("handling: $request");
    }
}

echo "\n=== class method trace ===\n";
$app = new App();
$trace = $app->handle("GET /users");
echo "frames: " . count($trace) . "\n";
echo "frame 0: " . $trace[0]['function'] . "\n";
echo "frame 0 class: " . ($trace[0]['class'] ?? 'none') . "\n";
echo "frame 0 type: " . ($trace[0]['type'] ?? 'none') . "\n";
echo "frame 1: " . $trace[1]['function'] . "\n";
echo "frame 1 class: " . ($trace[1]['class'] ?? 'none') . "\n";
echo "frame 2: " . $trace[2]['function'] . "\n";

// backtrace with limit
function deep3() { return debug_backtrace(0, 2); }
function deep2() { return deep3(); }
function deep1() { return deep2(); }

echo "\n=== limit ===\n";
$limited = deep1();
echo "limited frames: " . count($limited) . "\n";
echo "frame 0: " . $limited[0]['function'] . "\n";
echo "frame 1: " . $limited[1]['function'] . "\n";

// ignore args option (DEBUG_BACKTRACE_IGNORE_ARGS = 2)
function check_args() { return debug_backtrace(2); }
function caller_of_check() { return check_args(); }

echo "\n=== ignore args ===\n";
$no_args = caller_of_check();
echo "has args key: " . (array_key_exists('args', $no_args[0]) ? 'yes' : 'no') . "\n";

// debug_print_backtrace
function print_inner() {
    debug_print_backtrace();
}

function print_outer() {
    print_inner();
}

echo "\n=== print backtrace ===\n";
print_outer();

// empty trace at top level
echo "\n=== top level ===\n";
$top = debug_backtrace();
echo "top level frames: " . count($top) . "\n";
