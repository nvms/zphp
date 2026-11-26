<?php
// ReflectionExtension::info() prints the module as phpinfo() does, its
// directives in registration order
foreach (['spl', 'SPL', 'json', 'Reflection', 'ctype', 'random', 'date'] as $name) {
    ob_start();
    (new ReflectionExtension($name))->info();
    $text = ob_get_clean();
    // the default timezone depends on the configuration
    echo preg_replace('/^(Default timezone|date\.timezone) => .*$/m', '$1 => X', $text);
}
