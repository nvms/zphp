<?php
// regression: an exception thrown by an internal function captures the user
// call stack in its trace. previously native-thrown exceptions carried an
// empty trace and getTraceAsString() always returned just "#0 {main}".

function deep() { return strlen([]); }
function mid() { return deep(); }
function top() { return mid(); }

try {
    top();
} catch (\TypeError $e) {
    echo $e->getTraceAsString(), "\n";
}

echo "--- trace array ---\n";
try {
    top();
} catch (\TypeError $e) {
    $trace = $e->getTrace();
    echo "count: ", count($trace), "\n";
    foreach ($trace as $i => $frame) {
        echo "#$i ", $frame['function'], " line=", $frame['line'] ?? '?', "\n";
    }
}

echo "--- thrown from a static method ---\n";
class Service {
    public static function run(): int { return strlen([]); }
}
function callService() {
    return Service::run();
}
try {
    callService();
} catch (\TypeError $e) {
    echo $e->getTraceAsString(), "\n";
}

echo "--- thrown from an instance method ---\n";
class Worker {
    public function process(): int { return strlen([]); }
}
function callWorker() {
    return (new Worker)->process();
}
try {
    callWorker();
} catch (\TypeError $e) {
    echo $e->getTraceAsString(), "\n";
    foreach ($e->getTrace() as $i => $f) {
        echo "#$i function=", $f['function'],
             " class=", $f['class'] ?? '-',
             " type=", $f['type'] ?? '-', "\n";
    }
}

echo "--- user throw from an instance method ---\n";
class Validator {
    public function check(): void { throw new \DomainException('invalid'); }
}
try {
    (new Validator)->check();
} catch (\DomainException $e) {
    echo $e->getTraceAsString(), "\n";
}

echo "--- a user throw still works ---\n";
function userThrowInner() { throw new \RuntimeException('boom'); }
function userThrowOuter() { userThrowInner(); }
try {
    userThrowOuter();
} catch (\RuntimeException $e) {
    echo $e->getTraceAsString(), "\n";
}

echo "--- single level ---\n";
function single() { return strlen([]); }
try {
    single();
} catch (\TypeError $e) {
    echo count($e->getTrace()), " frame(s)\n";
}
