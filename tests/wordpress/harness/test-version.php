<?php
// minimal smoke: load WordPress's version file directly and check the
// $wp_version global gets populated. WordPress's wp-includes/version.php
// just defines a handful of constants and globals - no DB or HTTP needed
require __DIR__ . '/../app/wp-includes/version.php';

echo 'wp_version defined: ' . (isset($wp_version) ? 'y' : 'n') . "\n";
echo 'wp_version is string: ' . (is_string($wp_version) ? 'y' : 'n') . "\n";
echo 'tinymce_version defined: ' . (isset($tinymce_version) ? 'y' : 'n') . "\n";
echo 'required_php_version defined: ' . (isset($required_php_version) ? 'y' : 'n') . "\n";
echo 'required_mysql_version defined: ' . (isset($required_mysql_version) ? 'y' : 'n') . "\n";
