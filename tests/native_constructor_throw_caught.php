<?php
// a built-in constructor that throws lands in the catch with the frames
// around it intact

function open(string $path) {
    try {
        $f = @new SplFileObject($path);
        return "opened";
    } catch (RuntimeException $e) {
        return "caught " . get_class($e);
    }
}

$missing = __DIR__ . '/no-such-dir/no-such-file';
var_dump(open($missing));

try {
    $f = @new SplFileObject($missing);
    echo "not reached\n";
} catch (RuntimeException $e) {
    echo "top level caught ", get_class($e), "\n";
}

class Wrapper {
    public function make(string $path) {
        try {
            return @new SplFileObject($path);
        } catch (LogicException $e) {
            return "wrong catch";
        }
    }
}
try {
    (new Wrapper)->make($missing);
} catch (RuntimeException $e) {
    echo "outer caught ", get_class($e), "\n";
}

$results = array_map('open', [$missing, $missing]);
var_dump($results);
echo "done\n";
