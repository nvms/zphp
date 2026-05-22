<?php
// regression: getTraceAsString renders call arguments the way PHP does -
// quoted and truncated strings, Array / scalar placeholders - for plain
// functions and instance methods. also checks that an opcode-compiled
// native (count) is not framed into the trace.

function level2(string $label, int $count): void {
    throw new RuntimeException("fail at {$label}");
}
function level1(array $data): void {
    level2('inner', count($data));
}
try {
    level1([1, 2, 3]);
} catch (RuntimeException $e) {
    echo $e->getTraceAsString(), "\n";
}

class Service {
    public function run(string $name, array $opts, bool $flag): void {
        $this->step($name);
    }
    private function step(string $s): void {
        throw new LogicException("step {$s}");
    }
}
try {
    (new Service())->run('job', ['a' => 1], true);
} catch (LogicException $e) {
    echo $e->getTraceAsString(), "\n";
}

function withLongArg(string $s): void {
    throw new Exception('boom');
}
try {
    withLongArg('an argument long enough to be truncated');
} catch (Exception $e) {
    echo $e->getTraceAsString(), "\n";
}
