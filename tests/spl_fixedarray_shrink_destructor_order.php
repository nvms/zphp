<?php
class InvalidDestructor {
    public function __construct(
        private int $desiredSize,
        private SplFixedArray $obj,
    ) {}

    public function __destruct() {
        echo "In destructor\n";
        $this->obj->setSize($this->desiredSize);
        echo "Destroyed, size is now still ", $this->obj->getSize(), "\n";
    }
}

class DestructorLogger {
    public function __construct(private int $id) {}

    public function __destruct() {
        echo "Destroyed the logger with id ", $this->id, "\n";
    }
}

function test(int $desiredSize) {
    $obj = new SplFixedArray(5);
    $obj[0] = str_repeat("A", 10);
    $obj[1] = new DestructorLogger(1);
    $obj[2] = str_repeat('B', 10);
    $obj[3] = new InvalidDestructor($desiredSize, $obj);
    $obj[4] = new DestructorLogger(4);
    $obj->setSize(2);
    echo "Size is now ", $obj->getSize(), "\n";
    echo "Done\n";
}

echo "--- Smaller size test ---\n";
test(1);
echo "--- Equal size test ---\n";
test(2);
echo "--- Larger size test ---\n";
test(10);
?>
