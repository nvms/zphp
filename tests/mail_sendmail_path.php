<?php
// mail() hands the message to sendmail_path through the shell; the settings
// are startup-only, so each case runs a child with its own -d options
function run(array $ini, string $code): void {
    $cmd = escapeshellarg(PHP_BINARY);
    foreach ($ini as $k => $v) {
        $cmd .= ' -d ' . escapeshellarg("$k=$v");
    }
    $file = sys_get_temp_dir() . "/zphp_mail_sendmail_path_case.php";
    file_put_contents($file, "<?php\n" . $code);
    echo shell_exec($cmd . ' ' . escapeshellarg($file) . ' 2>&1');
    unlink($file);
}

run(['sendmail_path' => 'cat'], 'var_dump(mail("user@example.com", "Subject", "Body\r\nline", "From: a@b\r\nX-Y: z"));');
run(['sendmail_path' => 'cat'], 'var_dump(mail("a@b\r\n c", " Sub\tject \n", "m", ["X-A" => "1", "X-B" => ["2", "3"]]));');
run(['sendmail_path' => 'cat', 'mail.add_x_header' => '1'], 'var_dump(mail("a@b", "s", "m"));');
run(['sendmail_path' => 'cat', 'mail.cr_lf_mode' => 'lf'], 'var_dump(mail("a@b", "s", "a\r\nb", "X: 1"));');
run(['sendmail_path' => 'cat', 'mail.mixed_lf_and_crlf' => '1'], 'var_dump(mail("a@b", "s", "m", "X: 1"));');
run(['sendmail_path' => 'exit 3'], 'var_dump(mail("a@b", "s", "m"));');
run(['sendmail_path' => 'exit 75'], 'var_dump(mail("a@b", "s", "m"));');
run(['sendmail_path' => 'cat'], 'var_dump(mail("a@b", "s", "m", "X: 1\r\n\r\nY: 2"));');
run(['sendmail_path' => 'cat'], 'var_dump(ini_set("sendmail_path", "true"), ini_get("sendmail_path"), ini_get("mail.cr_lf_mode"));');

$cases = [
    [5 => "x"],
    ["To" => "x"],
    ["subject" => "x"],
    ["From" => ["a", "b"]],
    ["X" => ["k" => "v"]],
    ["X" => [1]],
    ["X" => new stdClass],
    ["X:Y" => "v"],
    ["X" => "a\nb"],
    ["X" => "a\rb"],
    ["X" => "a\r\nb"],
    ["X" => "a\0b"],
    ["X\0Y" => "v"],
];
foreach ($cases as $headers) {
    try {
        mail("a@b", "s", "m", $headers);
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
foreach ([["a\0", "s", "m"], ["a", "s\0", "m"], ["a", "s", "m\0"], ["a", "s", "m", "h\0"], ["a", "s", "m", "", "p\0"]] as $args) {
    try {
        mail(...$args);
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
