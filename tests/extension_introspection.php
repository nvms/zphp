<?php
// extension presence and the per-extension function lists php reports for them

var_dump(extension_loaded('json'), extension_loaded('JSON'), extension_loaded('Core'), extension_loaded('definitely_not_real'));

$loaded = get_loaded_extensions();
var_dump(in_array('Core', $loaded, true), in_array('json', $loaded, true), in_array('SPL', $loaded, true), in_array('spl', $loaded, true));

foreach (['json', 'JSON', 'ctype', 'pcre'] as $ext) {
    $funcs = get_extension_funcs($ext);
    sort($funcs);
    echo $ext, ': ', implode(' ', $funcs), "\n";
}

$core = get_extension_funcs('zend');
var_dump(in_array('strlen', $core, true), in_array('json_encode', $core, true));
$standard = get_extension_funcs('standard');
var_dump(in_array('str_replace', $standard, true), in_array('strlen', $standard, true), in_array('preg_match', $standard, true));

var_dump(get_extension_funcs('definitely_not_real'), get_extension_funcs('Reflection'), get_extension_funcs(''));
