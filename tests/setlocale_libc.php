<?php
var_dump(LC_ALL, LC_CTYPE, LC_NUMERIC, LC_MESSAGES);
var_dump(setlocale(LC_ALL, 0));
var_dump(setlocale(LC_CTYPE, 0));
var_dump(setlocale(LC_ALL, 'xx_NOPE', 'C'));
var_dump(setlocale(LC_ALL, ['nope', 'C.UTF-8']));
var_dump(setlocale(LC_ALL, 'nope'));
var_dump(setlocale(LC_ALL, null));
var_dump(setlocale(LC_NUMERIC, "0"));
var_dump(localeconv());
try { setlocale(LC_ALL, new stdClass); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { setlocale(LC_ALL, 'C', []); var_dump(setlocale(LC_ALL, 'nope', new stdClass)); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
setlocale(LC_ALL, str_repeat('x', 300));
