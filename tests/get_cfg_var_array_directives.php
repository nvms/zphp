<?php
// get_cfg_var() of a name given as name[key] directives is the array they
// build; name[] appends

$code = 'var_dump(get_cfg_var(\'ary\'), get_cfg_var(\'ary[a]\'), get_cfg_var(\'list\'), get_cfg_var(\'missing\'));';
echo shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d ary[a]=1 -d ary[b]=2 -d ary[7]=seven -d list[]=x -d list[]=y -r ' . escapeshellarg($code) . ' 2>&1');
