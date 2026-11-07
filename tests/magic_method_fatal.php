<?php
// a magic method whose signature php rejects stops the file before any of it
// runs
echo "not reached\n";
class Store {
    public function __get(string $name) {}
    public function __set(string $name, $value): bool { return true; }
}
