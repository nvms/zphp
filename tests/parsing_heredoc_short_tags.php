<?php
$s = <<<TXT
    line 1
    line 2
    TXT;
echo $s, "\n---\n";

$s = <<<TXT
        deeper
        line
        TXT;
echo $s, "\n---\n";

$s = <<<TXT
  one
TXT;
echo $s, "\n---\n";

// indented heredoc body must match closing-identifier indent (architectural - zphp permissive)

$s = <<<'NOW'
    nowdoc
    line2
    NOW;
echo $s, "\n---\n";

$s = <<<'NOW'
$literal_var
no interpolation
NOW;
echo $s, "\n---\n";

$s = <<<MSG
no leading
MSG;
echo "[$s]\n";

$s = <<<MSG
just-one
MSG;
echo "[$s]\n";

$s = <<<MSG

leading-blank

MSG;
var_dump($s);

$x = "ab";
$s = <<<TXT
trailing dollar: \$
escaped: \$$x
EOF in middle: not matching EOF
TXT;
echo $s, "\n---\n";

echo <<<INLINE
inline use
INLINE, "\n";

echo "echo: ", <<<X
heredoc-after-comma
X, "\n";

$x = 5;
?><html>
<?= $x + 1 ?>
<?= "string" ?>
</html><?php

echo "after-html\n";

$arr = ["a", "b"];
?><?= $arr[0] ?>=<?= $arr[1] ?>
<?php
echo "more\n";

$nums = [];
for ($i = 0; $i < 3; $i++) {
    $nums[] = $i * $i;
}
?><?= implode(",", $nums) ?>
<?php

if (true) {
?>
yes
<?php
} else {
?>
no
<?php
}

if (true): ?>
yes-alt
<?php
endif;

echo <<<TXT
end
TXT;
?>
