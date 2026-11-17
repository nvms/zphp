<?php
// get_extension_funcs("zend") lists the engine's own functions (extension
// Core), in any case
foreach (['zend', 'Zend', 'core'] as $name) {
    $funcs = get_extension_funcs($name);
    var_dump(is_array($funcs), in_array('strlen', $funcs), in_array('func_get_args', $funcs));
}
var_dump(get_extension_funcs('zendx'));
