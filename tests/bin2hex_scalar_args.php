<?php
// bin2hex and hex2bin take any scalar as a string
var_dump(bin2hex(12), bin2hex(1.5), bin2hex(true), bin2hex(false));
var_dump(bin2hex(hex2bin(1234)), hex2bin(true));
var_dump(hex2bin("zz"), hex2bin("abc"));
