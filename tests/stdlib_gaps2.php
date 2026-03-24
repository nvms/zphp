<?php

// strncmp (verify -1/0/1 return like strcmp)
echo strncmp("abc", "abd", 2) . "\n";
echo strncmp("abc", "abd", 3) . "\n";
echo strncmp("abc", "abc", 3) . "\n";

// shuffle - verify it doesn't crash and preserves elements
$nums = [1, 2, 3, 4, 5];
shuffle($nums);
sort($nums);
echo implode(",", $nums) . "\n";

// array_rand
$colors = ["red", "green", "blue", "yellow"];
$key = array_rand($colors);
echo (is_int($key) && $key >= 0 && $key < 4) ? "valid" : "invalid";
echo "\n";

// strip_tags
echo strip_tags("<p>Hello <b>world</b></p>") . "\n";

// pathinfo
$info = pathinfo("/var/www/test.php");
echo $info["dirname"] . "\n";
echo $info["basename"] . "\n";
echo $info["extension"] . "\n";
echo $info["filename"] . "\n";
