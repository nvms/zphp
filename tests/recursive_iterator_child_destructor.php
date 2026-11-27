<?php
// RecursiveIteratorIterator frees a finished child iterator as it leaves
// it (zend_iterator_dtor): the child's destructor runs then, from the code
// that moved the iteration on, before the parent's next element is read

class Node extends RecursiveArrayIterator
{
    public function next(): void
    {
        echo "next at ", var_export($this->key(), true), "\n";
        parent::next();
    }

    public function getChildren(): ?RecursiveArrayIterator
    {
        echo "children of ", $this->key(), "\n";
        return new Child($this->current());
    }
}

class Child extends RecursiveArrayIterator
{
    public function __destruct()
    {
        echo "child destructed\n";
        $e = new Exception('from the destructor');
        echo count($e->getTrace()), " frames\n";
    }
}

$it = new RecursiveIteratorIterator(new Node(['a' => [1, 2], 'b' => [3], 'c' => 4]));
foreach ($it as $k => $v) {
    echo "$k => $v\n";
}
echo "done\n";
