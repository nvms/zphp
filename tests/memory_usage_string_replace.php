<?php
// replacing a string with one of the same size leaves memory_get_usage()
// where it was, the first time too
$text = str_repeat('Eins zwei drei', 2000);
$replaced = preg_replace('/\s/', '-', $text);
$before = memory_get_usage();
$replaced = str_repeat($replaced, 1);
$after = memory_get_usage();
var_dump($after - $before);

$replaced = preg_replace_callback('/\s/', fn($m) => '-', $text);
$before = memory_get_usage();
$replaced = str_repeat($replaced, 1);
$after = memory_get_usage();
var_dump($after - $before);

$before = memory_get_usage();
$replaced = strtoupper($replaced);
$after = memory_get_usage();
var_dump($after - $before);
