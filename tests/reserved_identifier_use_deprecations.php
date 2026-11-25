<?php
// "_", "let" and "is" as import aliases, type names and class aliases are
// deprecated (zend_compile_use, zend_assert_valid_class_name)
error_reporting(E_ALL);
set_error_handler(function ($no, $msg, $file, $line) {
    echo "$no: $msg (line $line)\n";
    return true;
});
eval('namespace Foo\Bar {
    use stdClass as is;
    use stdClass as LET;
    use function strlen as _;
    use function strlen as is;
    use const PHP_INT_MAX as _;
    use const PHP_INT_MAX as Let;
}
namespace {
    use stdClass as _;
    function f(_ $a, \Foo\is $b, Let $c, Is $d, \Foo\IS $e) {}
}');
class_alias('stdClass', 'IS');
class_alias('stdClass', 'Foo\\LET');
class_alias('stdClass', 'Foo\\_');
class_alias('stdClass', 'Island');
echo "done\n";
