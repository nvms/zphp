<?php

// basic push/pop
$stack = new SplStack();
$stack->push("first");
$stack->push("second");
$stack->push("third");

echo $stack->count() . "\n";
echo $stack->top() . "\n";
echo $stack->bottom() . "\n";

echo $stack->pop() . "\n";
echo $stack->pop() . "\n";
echo $stack->count() . "\n";

// isEmpty
echo var_export($stack->isEmpty(), true) . "\n";
$stack->pop();
echo var_export($stack->isEmpty(), true) . "\n";

// push after empty
$stack->push("a");
$stack->push("b");
echo $stack->count() . "\n";
echo $stack->top() . "\n";

// shift/unshift
$stack2 = new SplStack();
$stack2->push(1);
$stack2->push(2);
$stack2->push(3);
$stack2->unshift(0);
echo $stack2->bottom() . "\n";
echo $stack2->count() . "\n";
echo $stack2->shift() . "\n";
echo $stack2->count() . "\n";

// instanceof Countable
echo var_export($stack2 instanceof Countable, true) . "\n";

// iteration (LIFO order)
$stack3 = new SplStack();
$stack3->push("x");
$stack3->push("y");
$stack3->push("z");
$result = "";
$stack3->rewind();
while ($stack3->valid()) {
    if ($result !== "") {
        $result = $result . ",";
    }
    $result = $result . $stack3->current();
    $stack3->next();
}
echo $result . "\n";

// mixed types
$stack4 = new SplStack();
$stack4->push(42);
$stack4->push("hello");
$stack4->push(true);
$stack4->push(3.14);
echo $stack4->count() . "\n";
echo $stack4->pop() . "\n";
echo $stack4->pop() . "\n";
echo $stack4->pop() . "\n";
echo $stack4->pop() . "\n";
