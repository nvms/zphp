<?php
// covers: inline HTML in function bodies, close tag as semicolon,
//   close tag terminating line comments, multi-static declarations,
//   inline HTML in switch/case, alt-syntax if with inline HTML

// basic inline HTML in function
function render_box($label, $value) {
    ?><div><?php echo $label; ?>: <?php echo $value ?></div><?php
}

render_box('color', 'red');
echo "\n";
// close tag terminates line comments
$x = 42; // this comment ends here ?><?php echo $x . "\n"; // 42

// multi-static declarations
function multi_counter() {
    static $a = 0, $b = 10;
    $a++;
    $b--;
    return "$a:$b";
}
echo multi_counter() . "\n"; // 1:9
echo multi_counter() . "\n"; // 2:8
echo multi_counter() . "\n"; // 3:7

// alt-syntax if with inline HTML
function greet_html($name, $show) {
    if ($show) :
        ?><p>Hello <?php echo $name ?></p>
<?php endif;
}
greet_html('Alice', true);
echo "\n";

// inline HTML in switch case
function render_tag($type) {
    switch ($type) {
        case 'bold':
            ?><b>bold</b><?php
            break;
        case 'italic':
            ?><i>italic</i><?php
            break;
        default:
            ?><span>plain</span><?php
            break;
    }
}
render_tag('bold');
render_tag('italic');
render_tag('plain');
echo "\n";

echo "done\n";
