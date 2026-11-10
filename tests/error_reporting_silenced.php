<?php
error_reporting(E_ALL);
set_error_handler(function ($no, $str) { echo "handler: ", error_reporting(), " ", $str, "\n"; return true; });
echo error_reporting(), "\n";
$x = @file_get_contents('/nonexistent/x');
@trigger_error("user", E_USER_WARNING);
$y = @$undefined;
echo error_reporting(), "\n";
var_dump(defined("ZEND_THREAD_SAFE"), ZEND_THREAD_SAFE, defined("ZEND_DEBUG_BUILD"));
try { @throw new Exception; } catch (Exception $e) {}
var_dump(error_reporting());
function thrower() { throw new Exception; }
try { @thrower(); } catch (Exception $e) {}
var_dump(error_reporting());
