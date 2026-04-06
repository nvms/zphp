<?php

// $argv and $argc are set in CLI mode
echo "type argv: " . gettype($argv) . "\n";
echo "type argc: " . gettype($argc) . "\n";
echo "argv is array: " . (is_array($argv) ? "true" : "false") . "\n";
echo "argc >= 1: " . ($argc >= 1 ? "true" : "false") . "\n";
echo "argv[0] is string: " . (is_string($argv[0]) ? "true" : "false") . "\n";
echo "argv[0] ends with argv.php: " . (str_ends_with($argv[0], "argv.php") ? "true" : "false") . "\n";
echo "argc matches count: " . ($argc === count($argv) ? "true" : "false") . "\n";

// $_SERVER['argv'] and $_SERVER['argc'] should also be set
echo "server argv type: " . gettype($_SERVER['argv']) . "\n";
echo "server argc type: " . gettype($_SERVER['argc']) . "\n";

echo "done\n";
