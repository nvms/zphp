<?php
// reading an internal function's parameter default that names a deprecated
// constant warns as reading the constant does

set_error_handler(function ($no, $msg) {
    echo "[$no] $msg\n";
    return true;
});
foreach (['date_sunrise', 'date_sunset', 'strlen'] as $function) {
    foreach ((new ReflectionFunction($function))->getParameters() as $param) {
        if (!$param->isDefaultValueAvailable()) continue;
        echo $function, ' $', $param->getName(), ' = ', var_export($param->getDefaultValue(), true), ' (', $param->getDefaultValueConstantName() ?? '-', ")\n";
    }
}
