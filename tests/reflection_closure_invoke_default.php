<?php
const D = 5;
$closure = function ($b = D, ?int $c = null, ...$rest) {};
$rm = (new ReflectionObject($closure))->getMethod('__invoke');
echo $rm, "\n";
foreach ($rm->getParameters() as $rp) {
    var_dump($rp->isOptional(), $rp->isDefaultValueAvailable(), (string) $rp->getType());
    foreach (['getDefaultValue', 'isDefaultValueConstant', 'getDefaultValueConstantName'] as $m) {
        try {
            var_dump($rp->$m());
        } catch (ReflectionException $e) {
            echo $m, ": ", $e->getMessage(), "\n";
        }
    }
}
$rp = new ReflectionParameter([$closure, '__invoke'], 0);
var_dump($rp->isDefaultValueAvailable());
// the closure itself still has its defaults
$rp = (new ReflectionFunction($closure))->getParameters()[0];
var_dump($rp->isDefaultValueAvailable(), $rp->getDefaultValue(), $rp->getDefaultValueConstantName());
