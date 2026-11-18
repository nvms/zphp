<?php
// DateTimeInterface declares all of php's methods, so an interface
// extending it is checked against each, and classes see them all

var_dump(get_class_methods('DateTimeInterface'));

set_error_handler(function ($no, $msg) {
    echo "[$no] $msg\n";
    return true;
});
eval('interface Offsets extends DateTimeInterface { function getOffset(): string; }');
var_dump(interface_exists('Offsets'));

$file = sys_get_temp_dir() . '/zphp_dti_' . getmypid() . '.php';
file_put_contents($file, "<?php\ninterface MyDateTimeInterface extends DateTimeInterface {\n    public function diff(): DateInterval;\n}\n");
$out = shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d display_errors=1 -d fatal_error_backtraces=0 ' . escapeshellarg($file) . ' 2>&1');
echo str_replace([$file, str_replace('/', DIRECTORY_SEPARATOR, $file)], 'FILE', $out), "\n";
unlink($file);

class Later extends DateTime {
    public function diff($other, $absolute = false): DateInterval {
        return parent::diff($other, $absolute);
    }
}
var_dump((new Later('2020-01-01'))->diff(new DateTime('2020-01-03'))->days);
