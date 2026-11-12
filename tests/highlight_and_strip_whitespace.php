<?php
// highlight_string, highlight_file/show_source and php_strip_whitespace
// follow zend_highlight and zend_strip over php's own tokens
$code = <<<'CODE'
<html><?php
/** doc */
namespace App;
// line comment
class Foo extends \Bar\Baz {
	const X = 0x1F + 1.5e3;
	public function run($a, &$b): ?string {
		$s = "value $a {$b->c} \n" . 'single' . __LINE__ . __CLASS__;
		return <<<EOT
heredoc $a
EOT;
	}
}
echo $obj->class, $x <=> $y, PHP_EOL; ?>
tail & <b>
CODE;

var_dump(highlight_string($code, true));
highlight_string("<?php echo 1;");
echo "\n";
$file = sys_get_temp_dir() . "/zphp_highlight_case.php";
file_put_contents($file, $code);
var_dump(highlight_file($file, true) === highlight_string($code, true));
var_dump(show_source($file, true) === highlight_string($code, true));
var_dump(php_strip_whitespace($file));
file_put_contents($file, "<?php\n/* c */ echo   1 ; // x\n return <<<A\na\nA;\n?>\n");
var_dump(php_strip_whitespace($file));
unlink($file);
var_dump(@highlight_file($file), @php_strip_whitespace($file));
var_dump(@highlight_file("data:,<?php echo 1; ?>"));
