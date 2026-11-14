<?php
// session.use_trans_sid: with cookies off, session_start makes the url
// rewriter carry the session id, through session.trans_sid_tags and hosts
ob_start();
$errors = [];
set_error_handler(function ($no, $msg) use (&$errors) { $errors[] = $msg; return true; });
session_save_path(sys_get_temp_dir());
ini_set('session.use_cookies', '0');
ini_set('session.use_only_cookies', '0');
ini_set('session.use_trans_sid', '1');
ini_set('session.trans_sid_hosts', 'example.com');
var_dump(ini_get('session.trans_sid_tags'), ini_get('url_rewriter.tags'));
session_id('zphptranssidcompat');
var_dump(session_start());
var_dump(ini_set('session.use_trans_sid', '0'));
output_add_rewrite_var('extra', '1');
?>
<a href="page.php">relative</a>
<a href="http://example.com/x">allowed host</a>
<a href="http://other.org/x">other host</a>
<form action="page.php"></form>
<img src="i.png">
<?php
var_dump(session_destroy());
ob_end_flush();
ob_end_flush();
print_r($errors);
