<?php
// an object whose closing brace is missing is never handed to __unserialize
// or __wakeup and is not destructed; what its data held is released when
// unserialize() ends, after the warning
set_error_handler(function ($no, $msg) {
    echo "warning: $msg\n";
    return true;
});

class U {
    public function __unserialize(array $data): void {
        echo "__unserialize(", count($data), ")\n";
    }
    public function __destruct() {
        echo "U::__destruct\n";
    }
}

class W {
    public $v = 0;
    public function __wakeup(): void {
        echo "__wakeup($this->v)\n";
    }
    public function __destruct() {
        echo "W::__destruct\n";
    }
}

class D {
    public function __destruct() {
        echo "D::__destruct\n";
    }
}

class Plain {
    public $v;
    public function __destruct() {
        echo "Plain::__destruct\n";
    }
}

foreach ([
    'unserialize, empty' => 'O:1:"U":0:{',
    'unserialize, data' => 'O:1:"U":1:{i:0;i:42;',
    'unserialize, wrong close' => 'O:1:"U":1:{i:0;i:42;;',
    'unserialize, nested' => 'a:1:{i:0;O:1:"U":0:{',
    'unserialize, holding an object' => 'O:1:"U":1:{i:0;O:1:"D":0:{}',
    'wakeup, empty' => 'O:1:"W":0:{',
    'wakeup, data' => 'O:1:"W":1:{s:1:"v";i:42;',
    'wakeup, nested' => 'a:2:{i:0;O:1:"W":1:{s:1:"v";i:1;}i:1;O:1:"W":0:{',
    'plain' => 'O:5:"Plain":1:{s:1:"v";i:1;',
    'plain holding an object' => 'O:5:"Plain":1:{s:1:"v";O:1:"D":0:{}',
    'complete then broken' => 'a:2:{i:0;O:1:"U":0:{}i:1;O:1:"U":0:{',
] as $name => $data) {
    echo "$name:\n";
    var_dump(unserialize($data));
    echo "\n";
}

echo "valid:\n";
var_dump(unserialize('a:2:{i:0;O:1:"U":1:{i:0;i:42;}i:1;O:1:"W":1:{s:1:"v";i:7;}}'));
echo "end\n";
