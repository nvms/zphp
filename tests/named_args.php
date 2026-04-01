<?php

// basic named arguments
function greet($greeting, $name) {
    return $greeting . ", " . $name . "!";
}

echo greet(name: "World", greeting: "Hello") . "\n";
echo greet(greeting: "Hi", name: "PHP") . "\n";

// mixed positional and named
function make_tag($tag, $content, $class) {
    return "<" . $tag . " class=\"" . $class . "\">" . $content . "</" . $tag . ">";
}

echo make_tag("div", content: "hello", class: "main") . "\n";

// named args with defaults
function config($host, $port, $debug) {
    return $host . ":" . $port . ($debug ? " [debug]" : "");
}

echo config(port: 8080, host: "localhost", debug: false) . "\n";
echo config(host: "0.0.0.0", debug: true, port: 3000) . "\n";

// global write-back
$counter = 0;

function bump() {
    global $counter;
    $counter = $counter + 10;
}

bump();
bump();
echo $counter . "\n";

// named args in constructor with promoted properties
class Box {
    public function __construct(
        public int $width,
        public int $height,
        public string $color = 'red',
    ) {}
}

$b = new Box(height: 20, width: 10, color: 'blue');
echo "{$b->width}x{$b->height}:{$b->color}\n"; // 10x20:blue

$b2 = new Box(height: 5, width: 3);
echo "{$b2->width}x{$b2->height}:{$b2->color}\n"; // 3x5:red
