<?php
// error_log() with message type 1 mails the message through sendmail_path to
// the destination, and fails without one (sendmail_path is startup-only, so
// a child runs with it)
$script = sys_get_temp_dir() . '/zphp_error_log_mail_case.php';
file_put_contents($script, '<?php
$headers = "From: test <mail@domain.tld>\nX-Mailer: test";
var_dump(error_log("Error message", 1, null));
var_dump(error_log("Error message with dest", 1, "default@domain.tld", null));
var_dump(error_log("Error message cust headers", 1, null, $headers));
var_dump(error_log("Error message with both", 1, "default@domain.tld", $headers));
');
echo shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d mail.add_x_header=0 -d sendmail_path=cat ' . escapeshellarg($script) . ' 2>&1');
unlink($script);
