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

// isset and unset
echo isset($config["host"]) ? "yes" : "no";
echo "\n";
echo isset($config["missing"]) ? "yes" : "no";
echo "\n";
unset($config["port"]);
echo isset($config["port"]) ? "yes" : "no";
echo "\n";

// instanceof ArrayAccess
echo ($config instanceof ArrayAccess) ? "is ArrayAccess" : "not ArrayAccess";
echo "\n";

// append syntax
class Stack implements ArrayAccess {
    private $items = [];

    public function offsetGet($key): mixed {
        return $this->items[$key] ?? null;
    }

    public function offsetSet($key, $value): void {
        if ($key === null) {
            $this->items[] = $value;
        } else {
            $this->items[$key] = $value;
        }
    }

    public function offsetExists($key): bool {
        return isset($this->items[$key]);
    }

    public function offsetUnset($key): void {
        unset($this->items[$key]);
    }

    public function count(): int {
        return count($this->items);
    }
}

$stack = new Stack();
$stack[] = "first";
$stack[] = "second";
echo $stack[0] . "\n";
echo $stack[1] . "\n";

// ArrayObject bracket syntax
$ao = new ArrayObject(["a" => 1, "b" => 2]);
$ao["c"] = 3;
echo $ao["a"] . "\n";
echo $ao["c"] . "\n";
echo ($ao instanceof ArrayAccess) ? "ao is ArrayAccess" : "ao not ArrayAccess";
echo "\n";

echo "done\n";
