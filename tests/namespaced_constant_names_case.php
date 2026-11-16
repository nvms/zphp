<?php
// the namespace part of a constant's name is matched in any case, the
// constant's own name exactly
namespace Foo\Bar {
    const LOCAL = 'local';
}

namespace {
    define('NS1\ns2\const1', 'value1');
    define('ns1\NS2\coNSt3', 'value3');

    echo NS1\ns2\const1, "\n";
    echo ns1\ns2\const1, "\n";
    echo Ns1\Ns2\const1, "\n";
    echo NS1\NS2\coNSt3, "\n";
    echo foo\bar\LOCAL, "\n";
    echo FOO\BAR\LOCAL, "\n";

    var_dump(defined('ns1\ns2\const1'), defined('NS1\NS2\const1'), defined('ns1\ns2\CONST1'));
    var_dump(constant('nS1\Ns2\const1'));
    var_dump(define('NS1\NS2\const1', 'again'));

    try {
        echo NS1\ns2\coNSt1, "\n";
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
    try {
        echo foo\bar\local, "\n";
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
