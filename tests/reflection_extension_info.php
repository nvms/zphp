<?php
// ReflectionExtension::info() prints the module as phpinfo() does, its
// directives in registration order
foreach (['spl', 'SPL', 'json', 'Reflection', 'ctype', 'random', 'date'] as $name) {
    ob_start();
    (new ReflectionExtension($name))->info();
    $text = ob_get_clean();
    // the default timezone and a distribution php's system tz database
    // depend on the configuration
    echo preg_replace('/^(Default timezone|date\.timezone|"Olson" Timezone Database Version) => .*$/m', '$1 => X', $text);
}
