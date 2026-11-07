<?php
// the cycle collector walks a long chain of objects without native recursion
// (php-src Zend/tests/gc/bug77345_gc_2)

class Node
{
    public static $destroyed = 0;
    public $previous;
    public $next;

    public function __destruct()
    {
        self::$destroyed++;
    }
}

function build($count)
{
    $first = new Node();
    $first->previous = $first;
    $first->next = $first;
    $list = $first;
    for ($i = 0; $i < $count; $i++) {
        $current = $list;
        $next = $list->next;
        $node = new Node();
        $node->previous = $current;
        $current->next = $node;
        $node->next = $next;
        $next->previous = $node;
        $list = $next;
    }
}

// automatic collection stays off while the chain grows, to keep this quick
gc_disable();
build(100000);
gc_enable();
gc_collect_cycles();
var_dump(Node::$destroyed);

echo "end\n";
