<?php
// `-m` lists the loaded modules, sorted by name in any case, then the zend
// extensions (the module lists themselves differ between builds)
$out = shell_exec(escapeshellarg(PHP_BINARY) . ' -n -m');
$lines = explode("\n", $out);
var_dump($lines[0]);
var_dump(in_array('Core', $lines), in_array('standard', $lines), in_array('[Zend Modules]', $lines));
$modules = array_slice($lines, 1, array_search('', $lines) - 1);
$sorted = $modules;
usort($sorted, 'strcasecmp');
var_dump($modules === $sorted);
var_dump(str_ends_with($out, "\n\n"));
