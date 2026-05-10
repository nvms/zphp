<?php
$name = "alice";
$age = 30;

echo <<<EOT
hello $name
you are $age
EOT;
echo "\n--\n";

echo <<<'EOT'
no $name interpolation
literal text
EOT;
echo "\n--\n";

$arr = ["a" => 1, "b" => 2];
$obj = new stdClass;
$obj->x = "hello";
$obj->nested = new stdClass;
$obj->nested->y = "world";

echo <<<EOT
simple: $name
array: {$arr["a"]} {$arr["b"]}
object: {$obj->x}
chain: {$obj->nested->y}
EOT;
echo "\n--\n";

echo <<<EOT
    indented
    line two
    EOT;
echo "\n--\n";

echo <<<EOT
        leading-space-content
    closer-less-indented
    EOT;
echo "\n--\n";

echo <<<EOT

EOT;
echo "[empty]\n--\n";

echo <<<'EOT'

EOT;
echo "[empty-nowdoc]\n--\n";

$items = ["x", "y", "z"];
echo <<<EOT
{$items[0]}-{$items[1]}-{$items[2]}
EOT;
echo "\n--\n";

class Box { public int $v = 42; public function get(): int { return $this->v; } }
$b = new Box;
echo <<<EOT
value: {$b->v}
method: {$b->get()}
EOT;
echo "\n--\n";

$x = "outer";
$func = function () use ($x) {
    return <<<EOT
inside: $x
EOT;
};
echo $func(), "\n--\n";

$multi = <<<EOT
line1
line2
line3
EOT;
echo $multi, "\n--\n";

$nowdoc = <<<'EOT'
$nope is not expanded
EOT;
echo $nowdoc, "\n--\n";

$mix = <<<EOT
"quoted" 'single' \\backslash\\ tab=\there
EOT;
echo $mix, "\n--\n";

echo <<<EOT
heredoc with \$dollar
and \n literal-n
EOT;
echo "\n--\n";

class Multi {
    public array $tags = ["red", "blue"];
}
$m = new Multi;
echo <<<EOT
tags: {$m->tags[0]} {$m->tags[1]}
EOT;
echo "\n--\n";

$arr = [["name" => "alice"], ["name" => "bob"]];
echo <<<EOT
first: {$arr[0]["name"]}
second: {$arr[1]["name"]}
EOT;
echo "\n--\n";

function getName(): string { return "world"; }
$name = getName();
echo <<<EOT
hello, $name!
EOT;
echo "\n--\n";

$d = "data";
echo <<<XML
<root>
    <item>$d</item>
</root>
XML;
echo "\n--\n";

$arr = [1, 2, 3];
echo <<<EOT
arr: $arr[0], $arr[1], $arr[2]
EOT;
echo "\n";
