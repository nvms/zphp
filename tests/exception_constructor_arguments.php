<?php
$e = new Exception(1);
var_dump($e->getMessage());
$e = new Exception(1.5, "7");
var_dump($e->getMessage(), $e->getCode());
class MyEx extends Exception {}
$e = new MyEx(true);
var_dump($e->getMessage());
try { new Exception(new stdClass); } catch (TypeError $t) { echo $t->getMessage(), "\n"; }
try { new Error([], 1); } catch (TypeError $t) { echo $t->getMessage(), "\n"; }
try { new Exception("a", "x"); } catch (TypeError $t) { echo $t->getMessage(), "\n"; }
try { new ErrorException(new stdClass); } catch (TypeError $t) { echo $t->getMessage(), "\n"; }
$e = new ErrorException(5, "3", 2, 7, 9);
var_dump($e->getMessage(), $e->getCode(), $e->getSeverity(), $e->getFile(), $e->getLine());
