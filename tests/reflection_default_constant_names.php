<?php
// a default's constant name outlives the reflector that read it, and asking
// about a parameter without a default is php's internal error

namespace App;

class Settings {
    const LEVEL = 3;
}
const MODE = 'fast';

function configure($required, $level = Settings::LEVEL, $mode = MODE, $plain = 1) {}

$names = [];
foreach ((new \ReflectionFunction('App\configure'))->getParameters() as $param) {
    if ($param->isDefaultValueAvailable() && $param->isDefaultValueConstant()) {
        $names[] = $param->getDefaultValueConstantName();
    }
}
// churn the heap so a dangling name would show
$junk = [];
for ($i = 0; $i < 1000; $i++) $junk[] = str_repeat('x', $i % 50);
var_dump($names);

$required = new \ReflectionParameter('App\configure', 'required');
foreach (['getDefaultValue', 'isDefaultValueConstant', 'getDefaultValueConstantName'] as $method) {
    try {
        $required->$method();
    } catch (\ReflectionException $e) {
        echo $method, ': ', $e->getMessage(), "\n";
    }
}
