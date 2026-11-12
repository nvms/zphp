<?php
// arguments of #[\SensitiveParameter] parameters are redacted in traces
function login(string $user, #[\SensitiveParameter] string $password, #[SensitiveParameter] string ...$extra) {
    debug_print_backtrace();
    $trace = debug_backtrace();
    var_dump($trace[0]['args'][1] instanceof SensitiveParameterValue, $trace[0]['args'][1]->getValue());
    throw new Exception('denied');
}
try {
    login('alice', 'hunter2', 'one', 'two');
} catch (Exception $e) {
    echo $e->getTraceAsString(), "\n";
}
class Vault {
    public function open(#[SensitiveParameter] $key, $label = 'main') {
        throw new RuntimeException('locked');
    }
}
try {
    (new Vault)->open('secret');
} catch (Exception $e) {
    echo $e->getTraceAsString(), "\n";
}
$v = new SensitiveParameterValue('hidden');
var_dump((array) $v, json_encode($v), $v->getValue());
print_r($v);
echo "\n";
try {
    $v->extra = 1;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
