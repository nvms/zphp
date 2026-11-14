<?php
// an object whose constructor can't be called is never constructed, so its
// destructor never runs (php gh-14456)

class PrivateUser {
    private function __construct() {}
    public function __destruct() { echo "destructor for ", __CLASS__, "\n"; }
}

class ProtectedUser {
    protected function __construct(public int $n) {}
    public function __destruct() { echo "destructor for ", __CLASS__, "\n"; }
    public static function make(): static { return new static(1); }
}

class Child extends ProtectedUser {}

try {
    new PrivateUser();
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

try {
    $name = 'ProtectedUser';
    new $name(5);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

try {
    new Child(2);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

$made = ProtectedUser::make();
unset($made);
echo "done\n";
