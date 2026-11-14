<?php
// a user function's #[\NoDiscard] warning is E_USER_WARNING, and the magic
// methods that return nothing can't be #[\NoDiscard]

set_error_handler(function (int $errno, string $errstr) {
    echo $errno === E_USER_WARNING ? "E_USER_WARNING" : "level $errno", ": $errstr\n";
    return true;
});

#[\NoDiscard]
function test(): int {
    return 0;
}

#[\NoDiscard("the count matters")]
function gen() {
    yield 1;
}

class C {
    #[\NoDiscard]
    public function m(): int { return 1; }
}

test();
gen();
(new C)->m();
(void) test();
$x = test();

foreach (['__construct', '__destruct', '__clone', '__set', '__unset', '__wakeup', '__unserialize'] as $magic) {
    $params = match ($magic) {
        '__set' => '$n, $v',
        '__unset' => '$n',
        '__unserialize' => 'array $d',
        default => '',
    };
    $code = "class M { #[\\NoDiscard] public function $magic($params) {} }";
    echo shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d display_errors=1 -d log_errors=0 -r ' . escapeshellarg($code) . ' 2>&1');
}
