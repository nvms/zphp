<?php

// autoloader example: spl_autoload_register with __DIR__-based class loading

spl_autoload_register(function ($class) {
    $file = __DIR__ . "/Models/" . $class . ".php";
    if (file_exists($file)) {
        require $file;
    }
});

// these classes are loaded on demand by the autoloader
$user = new User("Alice", "alice@example.com");
echo $user->display() . "\n";

$post = new Post("Hello World", $user->name);
echo $post->summary() . "\n";

// verify classes are available after autoloading
echo (class_exists("User") ? "User loaded" : "User missing") . "\n";
echo (class_exists("Post") ? "Post loaded" : "Post missing") . "\n";

echo "done\n";
