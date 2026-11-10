<?php
// php's strip_tags state machine: php code, comments, quotes, nesting,
// doctype, <?xml, and the allowed tag list in each form it takes
$cases = [
    "hello <b>world</b>",
    "NEAT <? cool < blah ?> STUFF",
    "NEAT <? cool > blah ?> STUFF",
    "NEAT <!-- cool < blah --> STUFF",
    "NEAT <!-- cool > blah --> STUFF",
    "NEAT <? echo \"\\\"\"?> STUFF",
    "NEAT <? cool < blah ?> STUFF",
    "TESTS ?!!?!?!!!?!!",
    "<html>hello</html><?php echo hello ?>",
    "hello <img title=\"<\"> world",
    "hello <img title=\">\"> world",
    "hello <img title=\">_<\"> world",
    "hello <img title='>_<'> world",
    "a < b and c > d",
    "<html>11 < 12. 123 >22</html>",
    "<!DOCTYPE html><p>x</p>",
    "<?xml version=\"1.0\"?><a>x</a>",
    "x<a\0b>y\0z",
    "<a <b>>text</a>",
    "<p>one</p><br/>two<br />three",
];
foreach ($cases as $c) {
    var_dump(strip_tags($c));
    var_dump(strip_tags($c, "<p><b>"));
    var_dump(strip_tags($c, ["a", "BR"]));
}
var_dump(strip_tags("<htmL>hello</htmL>", "<html>"));
var_dump(strip_tags("<html>hello</html>", "<HTML>"));
var_dump(strip_tags("<p>x</p>", [1, "p"]));
var_dump(strip_tags("<1>x</1>", [1]));
var_dump(strip_tags(" I am html string \0", null));
try {
    strip_tags("a", fopen("php://memory", "r"));
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    strip_tags("a", new stdClass);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
