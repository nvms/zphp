<?php
class Test {
    public function __construct(public int $n = 0) {
        throw new Exception("ctor $n");
    }
    public function __destruct() {
        echo "__destruct\n";
    }
}
try {
    (new ReflectionClass('Test'))->newInstance(1);
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
try {
    $obj = (new ReflectionClass('Test'))->newInstanceArgs([2]);
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
try {
    $obj = (new ReflectionClass('Test'))->newInstanceArgs(['n' => 3]);
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
echo "done\n";
