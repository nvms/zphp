<?php

// basic ob_start / ob_get_clean
ob_start();
echo "buffered";
$content = ob_get_clean();
echo "got: " . $content . "\n";

// ob_get_contents (non-destructive)
ob_start();
echo "peek";
$c1 = ob_get_contents();
$c2 = ob_get_contents();
ob_end_clean();
echo "peek1: " . $c1 . "\n";
echo "peek2: " . $c2 . "\n";

// ob_get_level
echo "level0: " . ob_get_level() . "\n";
ob_start();
echo "level1: " . ob_get_level() . "\n";
ob_start();
echo "level2: " . ob_get_level() . "\n";
ob_end_clean();
echo "level1b: " . ob_get_level() . "\n";
ob_end_clean();
echo "level0b: " . ob_get_level() . "\n";

// nested buffering
ob_start();
echo "outer";
ob_start();
echo "inner";
$inner = ob_get_clean();
echo " + " . $inner;
$outer = ob_get_clean();
echo "nested: " . $outer . "\n";

// ob_end_flush - content stays in output
ob_start();
echo "flushed";
ob_end_flush();
echo "\n";

// ob_clean - discard current buffer content
ob_start();
echo "discard this";
ob_clean();
echo "kept";
$result = ob_get_clean();
echo "clean: " . $result . "\n";

// ob_get_length
ob_start();
echo "12345";
$len = ob_get_length();
ob_end_clean();
echo "length: " . $len . "\n";

// ob_get_clean on empty stack
$r = ob_get_clean();
echo "empty stack: " . var_export($r, true) . "\n";

// ob_end_clean on empty stack
$r = @ob_end_clean();
echo "end empty: " . var_export($r, true) . "\n";

// ob_end_flush on empty stack
$r = @ob_end_flush();
echo "flush empty: " . var_export($r, true) . "\n";

// ob_list_handlers
ob_start();
ob_start();
$handlers = ob_list_handlers();
echo "handlers: " . count($handlers) . "\n";
echo "handler0: " . $handlers[0] . "\n";
ob_end_clean();
ob_end_clean();

// ob_implicit_flush (no-op, just shouldn't error)
ob_implicit_flush(1);
echo "implicit: ok\n";

echo "done\n";
