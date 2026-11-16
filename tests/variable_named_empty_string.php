<?php
// ${''}, and variable variables whose name converts to "" (null, false)

$null = null;
$false = false;
$empty = '';

$$null = 'set through null';
var_dump(${''});
var_dump($$false);
var_dump(isset($$empty));

${''} = [1];
$$null['a'] = 5;
var_dump(${''});

unset(${''});
var_dump(isset(${''}));

$$empty['k'] = &$$null;
var_dump(array_keys(${''}));
unset(${''});

$$null += $$false['a'] = &$$empty;
var_dump(array_keys(${''}));
unset(${''});

try {
    $$null -= $$false['a'] = &$$empty;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

function scoped() {
    $n = null;
    $$n = 'local';
    var_dump(${''});
    var_dump(array_key_exists('', get_defined_vars()));
}
scoped();
