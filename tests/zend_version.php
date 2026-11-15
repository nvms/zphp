<?php
// the Zend Engine version php 8.5 reports: 4.5 and php's release
var_dump(preg_match("/^4\\.5\\.\\d+$/", zend_version()), explode(".", zend_version())[2] === explode(".", PHP_VERSION)[2]);
$f = new ReflectionFunction("zend_version"); var_dump($f->getExtensionName(), $f->getNumberOfParameters());
