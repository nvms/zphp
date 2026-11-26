<?php
// substr_replace holds each subject element as it was: a replacement's
// __toString that overwrites the referenced element doesn't change it
class Overwrite {
    public function __toString(): string {
        $GLOBALS['subject'] = 'gone';
        return '';
    }
}
class Append {
    public function __toString(): string {
        $GLOBALS['subject'] .= "BBBB";
        return '-';
    }
}
class Add {
    public function __toString(): string {
        $GLOBALS['subject'] += 5;
        return '+';
    }
}

$subject = str_repeat('A', 40);
$out = substr_replace([&$subject], [new Overwrite], 40, 0);
var_dump($out, $subject);
$subject = str_repeat('A', 40);
$out = substr_replace([&$subject, 'x'], [new Append, new Append], 2, 1);
var_dump($out, $subject);
$subject = '7' . str_repeat('A', 9);
$out = @substr_replace([&$subject], [new Add], 1, 0);
var_dump($out, $subject);
