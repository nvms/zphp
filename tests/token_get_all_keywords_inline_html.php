<?php
$src = '<?php echo "hi";';
$t = token_get_all($src);
foreach ($t as $tk) {
    if (is_array($tk)) echo token_name($tk[0]), "|", $tk[1], "\n";
    else echo "L:", $tk, "\n";
}

echo "---\n";

$src = '<?php $name = "alice"; echo $name;';
$t = token_get_all($src);
foreach ($t as $tk) {
    if (is_array($tk)) echo token_name($tk[0]), "|", $tk[1], "\n";
    else echo "L:", $tk, "\n";
}

echo "---\n";

$src = '<?php function foo() { return 42; }';
$t = token_get_all($src);
$names = [];
foreach ($t as $tk) {
    if (is_array($tk)) $names[] = token_name($tk[0]);
}
print_r($names);

echo "---\n";

$src = '<?php
class Foo {
    public int $x = 1;
    public function bar(): int { return $this->x; }
}';
$t = token_get_all($src);
$class_seen = false;
$function_seen = false;
$return_seen = false;
foreach ($t as $tk) {
    if (is_array($tk)) {
        if ($tk[0] === T_CLASS) $class_seen = true;
        if ($tk[0] === T_FUNCTION) $function_seen = true;
        if ($tk[0] === T_RETURN) $return_seen = true;
    }
}
echo $class_seen ? "y" : "n", " ", $function_seen ? "y" : "n", " ", $return_seen ? "y" : "n", "\n";

echo "---\n";

$src = '<?php $a = 1 + 2;';
$t = token_get_all($src);
foreach ($t as $tk) {
    if (is_array($tk)) echo token_name($tk[0]), ":", trim($tk[1]), " ";
    else echo $tk, " ";
}
echo "\n";

echo "---\n";

$src = "before<?php echo \"hi\"; ?>after";
$t = token_get_all($src);
$has_inline = false;
foreach ($t as $tk) {
    if (is_array($tk) and $tk[0] === T_INLINE_HTML) $has_inline = true;
}
echo $has_inline ? "y" : "n", "\n";

echo "---\n";

$src = '<?php $x = "hello world";';
$t = token_get_all($src);
$has_var = false;
$has_str = false;
foreach ($t as $tk) {
    if (is_array($tk)) {
        if ($tk[0] === T_VARIABLE) $has_var = true;
        if ($tk[0] === T_CONSTANT_ENCAPSED_STRING) $has_str = true;
    }
}
echo $has_var ? "y" : "n", " ", $has_str ? "y" : "n", "\n";

echo "---\n";

$src = '<?php // comment
$x = 1;
/* block comment */';
$t = token_get_all($src);
$line_c = false;
$block_c = false;
foreach ($t as $tk) {
    if (is_array($tk)) {
        if ($tk[0] === T_COMMENT) $line_c = true;
        if ($tk[0] === T_DOC_COMMENT or $tk[0] === T_COMMENT) {
            if (str_starts_with($tk[1], "/*")) $block_c = true;
        }
    }
}
echo $line_c ? "y" : "n", " ", $block_c ? "y" : "n", "\n";

echo "---\n";

$src = "<?php\n// hello\n\$x = 1;\n";
$t = token_get_all($src);
echo count($t) > 3 ? "y" : "n", "\n";

echo "---\n";

echo defined("T_VARIABLE") ? "y" : "n", "\n";
echo defined("T_STRING") ? "y" : "n", "\n";
echo defined("T_OPEN_TAG") ? "y" : "n", "\n";
echo defined("T_INLINE_HTML") ? "y" : "n", "\n";
echo defined("T_CONSTANT_ENCAPSED_STRING") ? "y" : "n", "\n";

echo is_int(T_VARIABLE) ? "y" : "n", "\n";

echo strlen(token_name(T_VARIABLE)) > 0 ? "y" : "n", "\n";
echo token_name(T_VARIABLE), "\n";
echo token_name(T_STRING), "\n";
echo token_name(T_OPEN_TAG), "\n";

$src = '<?php echo 42;';
echo count(token_get_all($src)), "\n";
