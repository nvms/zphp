<?php

// basic strstr
echo strstr("hello world", "world") . "\n";
echo strstr("hello world", "o") . "\n";

// before_needle
echo strstr("hello world", "world", true) . "\n";
echo strstr("hello world", "o", true) . "\n";

// not found
var_dump(strstr("hello world", "xyz"));

// strchr alias
echo strchr("foo@bar.com", "@") . "\n";
