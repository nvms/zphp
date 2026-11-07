<?php
// php requires each magic method's parameter count while compiling
echo "not reached\n";
abstract class Proxy {
    abstract public function __call(string $name, array $args, $extra);
}
