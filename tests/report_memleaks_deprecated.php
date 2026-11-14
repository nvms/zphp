<?php
// turning report_memleaks off is deprecated in php 8.5
set_error_handler(function ($no, $msg) { echo $no, ": ", $msg, "\n"; return true; });
var_dump(ini_get('report_memleaks'));
var_dump(ini_set('report_memleaks', '0'));
var_dump(ini_set('report_memleaks', 'on'));
var_dump(ini_get('report_memleaks'));
