<?php
// the error_log file is created with error_log_mode, 0644 by default

$old = umask(0);
$file = sys_get_temp_dir() . '/zphp_error_log_mode_' . getmypid() . '.log';
foreach ([null, '0600', '0640', '0', '01777'] as $mode) {
    @unlink($file);
    if ($mode !== null) var_dump(ini_set('error_log_mode', $mode) !== false);
    ini_set('error_log', $file);
    error_log('entry');
    clearstatcache();
    printf("%s: %o\n", $mode ?? 'default', fileperms($file) & 0777);
}
unlink($file);
umask($old);
