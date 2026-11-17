<?php
// the classes the standard extension declares, in php's registration order
// and sorted

$standard = new ReflectionExtension('standard');
echo implode(', ', $standard->getClassNames()), "\n";
$classNames = $standard->getClassNames();
sort($classNames);
echo implode(', ', $classNames), "\n";
echo implode(', ', array_keys($standard->getClasses())), "\n";
var_dump((new ReflectionClass('__PHP_Incomplete_Class'))->getExtensionName());
var_dump((new ReflectionClass('StreamBucket'))->getExtensionName());
