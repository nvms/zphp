<?php

// string indexing
$s = "hello";
echo $s[0] . "\n";
echo $s[4] . "\n";
echo $s[1] . $s[2] . "\n";

// user-defined class with offsetGet/offsetSet
class Config implements ArrayAccess {
    private $data = [];

    public function offsetGet($key): mixed {
        return $this->data[$key] ?? null;
    }

    public function offsetSet($key, $value): void {
        $this->data[$key] = $value;
    }

    public function offsetExists($key): bool {
        return isset($this->data[$key]);
    }

    public function offsetUnset($key): void {
        unset($this->data[$key]);
    }
}

$config = new Config();
$config["host"] = "localhost";
$config["port"] = 3306;
echo $config["host"] . "\n";
echo $config["port"] . "\n";

// overwrite
$config["host"] = "127.0.0.1";
echo $config["host"] . "\n";

// ArrayObject bracket syntax
$ao = new ArrayObject(["a" => 1, "b" => 2]);
$ao["c"] = 3;
echo $ao["a"] . "\n";
echo $ao["c"] . "\n";

echo "done\n";
