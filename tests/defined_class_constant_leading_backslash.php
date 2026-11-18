<?php
// defined() finds a class constant whose class is written with a leading
// backslash, as the class lookup skips it

namespace ns;

const ok = 0;
class foo {
    const ok = 0;
}

foreach (['ns\ok', '\ns\ok', 'ns\foo::ok', '\ns\foo::ok', '\ns\foo::bug', '\ns\bar::bug'] as $name) {
    echo $name, ': ';
    var_dump(defined($name));
}
var_dump(constant('\ns\foo::ok'));
