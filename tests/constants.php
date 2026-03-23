<?php

echo PHP_EOL === "\n" ? "true" : "false";
echo "\n";

echo PHP_INT_SIZE;
echo "\n";

echo PHP_SAPI;
echo "\n";

echo DIRECTORY_SEPARATOR;
echo "\n";

echo STR_PAD_LEFT;
echo "\n";

echo STR_PAD_RIGHT;
echo "\n";

echo str_pad('x', 5, '.', STR_PAD_LEFT);
echo "\n";

echo str_pad('x', 5, '.', STR_PAD_RIGHT);
echo "\n";

define('MY_CONST', 42);
echo MY_CONST;
echo "\n";

const APP_NAME = 'zphp';
echo APP_NAME;
echo "\n";

echo defined('MY_CONST') ? 'true' : 'false';
echo "\n";

echo defined('NOPE') ? 'true' : 'false';
echo "\n";

echo constant('MY_CONST');
echo "\n";

echo TRUE ? '1' : '0';
echo "\n";

echo FALSE ? '1' : '0';
echo "\n";

echo is_null(NULL) ? 'true' : 'false';
echo "\n";
