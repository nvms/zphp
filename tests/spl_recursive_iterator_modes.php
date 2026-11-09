<?php
// RecursiveIteratorIterator's state machine over a directory-like tree and a
// site menu: every mode, depth limits, empty branches, and the tree printer

$fs = [
    'src' => [
        'Controller' => ['HomeController.php' => 1200, 'Admin' => ['UserController.php' => 900, 'empty' => []]],
        'Kernel.php' => 300,
        'cache' => [],
    ],
    'public' => ['index.php' => 80, 'assets' => ['app.css' => 5000, 'app.js' => 7000]],
    'README.md' => 400,
    'var' => [],
];

$modes = [
    'LEAVES_ONLY' => RecursiveIteratorIterator::LEAVES_ONLY,
    'SELF_FIRST' => RecursiveIteratorIterator::SELF_FIRST,
    'CHILD_FIRST' => RecursiveIteratorIterator::CHILD_FIRST,
];

foreach ($modes as $name => $mode) {
    foreach ([-1, 0, 1, 2] as $max) {
        $it = new RecursiveIteratorIterator(new RecursiveArrayIterator($fs), $mode);
        if ($max >= 0) {
            $it->setMaxDepth($max);
        }
        $paths = [];
        foreach ($it as $file => $size) {
            $parts = [];
            for ($d = 0; $d <= $it->getDepth(); $d++) {
                $parts[] = $it->getSubIterator($d)->key();
            }
            $paths[] = implode('/', $parts) . (is_array($size) ? '/' : " ($size)");
        }
        echo "$name max=", var_export($it->getMaxDepth(), true), ":\n  ", implode("\n  ", $paths), "\n";
    }
}

// a branch whose children are all empty yields nothing in LEAVES_ONLY mode
$sparse = ['a' => [], 'b' => ['c' => []], 'd' => 1];
var_dump(iterator_to_array(new RecursiveIteratorIterator(new RecursiveArrayIterator($sparse))));
var_dump(iterator_count(new RecursiveIteratorIterator(new RecursiveArrayIterator([[], [[]]]))));

// total size of the tree, leaves only
$total = 0;
foreach (new RecursiveIteratorIterator(new RecursiveArrayIterator($fs)) as $size) {
    $total += $size;
}
echo "total bytes: $total\n";

// a menu printed as an indented outline with begin/end hooks
class MenuPrinter extends RecursiveIteratorIterator
{
    public function beginIteration(): void { echo "<nav>\n"; }
    public function endIteration(): void { echo "</nav>\n"; }
    public function beginChildren(): void { echo str_repeat('  ', $this->getDepth()), "<ul>\n"; }
    public function endChildren(): void { echo str_repeat('  ', $this->getDepth() + 1), "</ul>\n"; }
}

$menu = [
    'Home' => '/',
    'Products' => ['Laptops' => '/laptops', 'Phones' => ['Android' => '/android', 'iOS' => '/ios']],
    'About' => '/about',
];
$printer = new MenuPrinter(new RecursiveArrayIterator($menu), RecursiveIteratorIterator::SELF_FIRST);
foreach ($printer as $label => $link) {
    $indent = str_repeat('  ', $printer->getDepth() + 1);
    echo $indent, is_array($link) ? "$label:" : "<a href=\"$link\">$label</a>", "\n";
}

// the same menu as an ASCII tree
$tree = new RecursiveTreeIterator(new RecursiveArrayIterator($menu));
foreach ($tree as $line) {
    echo $line, "\n";
}
$tree = new RecursiveTreeIterator(new RecursiveArrayIterator($fs), RecursiveTreeIterator::BYPASS_CURRENT);
foreach ($tree as $key => $value) {
    echo $key, is_array($value) ? '' : " = $value", "\n";
}
$tree = new RecursiveTreeIterator(new RecursiveArrayIterator($menu), 0);
$tree->setPrefixPart(RecursiveTreeIterator::PREFIX_LEFT, '> ');
$tree->setPostfix(' <');
foreach ($tree as $key => $value) {
    echo $key, ' :: ', $value, "\n";
}

// a node class that is its own RecursiveIterator, and children that fail
class Node implements RecursiveIterator
{
    private int $pos = 0;

    public function __construct(private array $children, private bool $broken = false) {}
    public function current(): mixed { return $this->children[$this->pos][0]; }
    public function key(): mixed { return $this->pos; }
    public function next(): void { $this->pos++; }
    public function rewind(): void { $this->pos = 0; }
    public function valid(): bool { return $this->pos < count($this->children); }
    public function hasChildren(): bool { return isset($this->children[$this->pos][1]); }
    public function getChildren(): ?RecursiveIterator
    {
        if ($this->broken && $this->children[$this->pos][0] === 'bad') {
            throw new RuntimeException('cannot read bad');
        }
        return new Node($this->children[$this->pos][1], $this->broken);
    }
}

$nodes = [['root', [['bad', [['hidden']]], ['ok', [['leaf']]]]], ['tail']];
foreach ([0, RecursiveIteratorIterator::CATCH_GET_CHILD] as $flags) {
    try {
        foreach (new RecursiveIteratorIterator(new Node($nodes, true), RecursiveIteratorIterator::SELF_FIRST, $flags) as $v) {
            echo "node $v\n";
        }
    } catch (RuntimeException $e) {
        echo "caught: ", $e->getMessage(), "\n";
    }
}

try {
    new RecursiveIteratorIterator(new ArrayIterator([1]));
} catch (InvalidArgumentException $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
try {
    (new RecursiveIteratorIterator(new RecursiveArrayIterator([])))->setMaxDepth(-2);
} catch (ValueError $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
