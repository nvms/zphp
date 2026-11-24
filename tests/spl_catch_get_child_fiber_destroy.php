<?php
// CATCH_GET_CHILD swallows exceptions from hasChildren() and getChildren(),
// but not the unwinding that destroys a fiber suspended inside them: the
// finally blocks run once and the iteration doesn't go on
class SuspendingChildren extends RecursiveArrayIterator {
    public function getChildren(): ?RecursiveArrayIterator {
        try {
            echo "getChildren suspends\n";
            Fiber::suspend();
        } finally {
            echo "getChildren finally\n";
        }
        return null;
    }
}

class SuspendingHasChildren extends RecursiveArrayIterator {
    public function hasChildren(): bool {
        try {
            echo "hasChildren suspends\n";
            Fiber::suspend();
        } finally {
            echo "hasChildren finally\n";
        }
        return false;
    }
}

$cases = [
    'RecursiveIteratorIterator, getChildren' => fn() => new RecursiveIteratorIterator(
        new SuspendingChildren([[1], [2]]),
        RecursiveIteratorIterator::LEAVES_ONLY,
        RecursiveIteratorIterator::CATCH_GET_CHILD,
    ),
    'RecursiveIteratorIterator, hasChildren' => fn() => new RecursiveIteratorIterator(
        new SuspendingHasChildren([1, 2]),
        RecursiveIteratorIterator::LEAVES_ONLY,
        RecursiveIteratorIterator::CATCH_GET_CHILD,
    ),
    'RecursiveCachingIterator, getChildren' => fn() => new RecursiveCachingIterator(
        new SuspendingChildren([[1], [2]]),
        CachingIterator::CATCH_GET_CHILD,
    ),
    'RecursiveCachingIterator, hasChildren' => fn() => new RecursiveCachingIterator(
        new SuspendingHasChildren([1, 2]),
        CachingIterator::CATCH_GET_CHILD,
    ),
];

foreach ($cases as $name => $make) {
    echo "$name:\n";
    $fiber = new Fiber(function () use ($make) {
        foreach ($make() as $k => $v) {
            echo "item $k\n";
        }
        echo "not reached\n";
    });
    $fiber->start();
    unset($fiber);
    echo "destroyed\n";
}

// an ordinary exception is still swallowed
class Throwing extends RecursiveArrayIterator {
    public function getChildren(): ?RecursiveArrayIterator {
        throw new Exception('boom');
    }
}
foreach (new RecursiveIteratorIterator(new Throwing([[1], 2]), RecursiveIteratorIterator::LEAVES_ONLY, RecursiveIteratorIterator::CATCH_GET_CHILD) as $k => $v) {
    echo "caught case: $k => ", json_encode($v), "\n";
}
echo "done\n";
