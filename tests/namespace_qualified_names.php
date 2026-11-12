<?php
namespace A\B {
    function f() { return __FUNCTION__; }
    const C = 'A\B\C';
}
namespace A {
    function g() { return __FUNCTION__; }
    echo B\f(), "\n";
    echo B\C, "\n";
    echo namespace\B\f(), "\n";
    echo \A\B\f(), "\n";
}
namespace X {
    use A\B as Alias;
    use A as AA;
    echo Alias\f(), "\n";
    echo alias\f(), "\n";
    echo Alias\C, "\n";
    echo AA\B\C, "\n";
    echo AA\g(), "\n";
    var_dump(\INI_ALL, INI_ALL);
}
