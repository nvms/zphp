<?php

// basic comparison
echo version_compare("1.0.0", "1.0.1") . "\n";
echo version_compare("1.0.1", "1.0.0") . "\n";
echo version_compare("1.0.0", "1.0.0") . "\n";

// with operator
echo version_compare("7.4.0", "8.0.0", "<") ? "true" : "false";
echo "\n";
echo version_compare("8.1.0", "8.0.0", ">=") ? "true" : "false";
echo "\n";
echo version_compare("1.2.3", "1.2.3", "==") ? "true" : "false";
echo "\n";
echo version_compare("1.0", "1.0.0", "eq") ? "true" : "false";
echo "\n";
echo version_compare("2.0", "1.0", "!=") ? "true" : "false";
echo "\n";

// sapi name
echo php_sapi_name() . "\n";
