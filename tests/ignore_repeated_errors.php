<?php
// with ignore_repeated_errors, a message equal to the last one from the same
// line (any line with ignore_repeated_source) is neither shown nor recorded
ini_set('display_errors', '1');
ini_set('log_errors', '0');
ini_set('html_errors', '0');
ini_set('ignore_repeated_errors', '1');
ob_start();
$x = $u + $u;
$first = ob_get_clean();
echo substr_count($first, 'Undefined variable $u'), "\n";
echo error_get_last()['line'], "\n";
ob_start();
$x = $u;
$second = ob_get_clean();
echo substr_count($second, 'Undefined variable $u'), "\n";
echo error_get_last()['line'], "\n";
ini_set('ignore_repeated_source', '1');
ob_start();
$x = $u;
$x = $w;
$x = $w;
$third = ob_get_clean();
echo substr_count($third, 'Undefined variable $u'), " ", substr_count($third, 'Undefined variable $w'), "\n";
echo error_get_last()['line'], "\n";
ini_set('ignore_repeated_errors', '0');
ob_start();
$x = $w;
$fourth = ob_get_clean();
echo substr_count($fourth, 'Undefined variable $w'), "\n";
