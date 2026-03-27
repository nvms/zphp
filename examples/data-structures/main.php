<?php
// covers: SplStack, SplQueue, SplPriorityQueue, SplFixedArray, array_push, array_pop, array_shift, array_unshift, count, usort, array_splice, array_slice, array_reverse, array_chunk, array_unique, array_fill

// --- stack (LIFO) ---

class Stack {
    private array $items = [];

    public function push($item): void {
        $this->items[] = $item;
    }

    public function pop() {
        if (empty($this->items)) {
            return null;
        }
        return array_pop($this->items);
    }

    public function peek() {
        if (empty($this->items)) {
            return null;
        }
        return $this->items[count($this->items) - 1];
    }

    public function size(): int {
        return count($this->items);
    }

    public function isEmpty(): bool {
        return empty($this->items);
    }

    public function toArray(): array {
        return array_reverse($this->items);
    }
}

$stack = new Stack();
$stack->push('a');
$stack->push('b');
$stack->push('c');

echo "Stack:\n";
echo "  peek: " . $stack->peek() . "\n";
echo "  size: " . $stack->size() . "\n";
echo "  pop: " . $stack->pop() . "\n";
echo "  pop: " . $stack->pop() . "\n";
echo "  size: " . $stack->size() . "\n";
echo "  remaining: " . implode(', ', $stack->toArray()) . "\n";

// --- queue (FIFO) ---

class Queue {
    private array $items = [];

    public function enqueue($item): void {
        $this->items[] = $item;
    }

    public function dequeue() {
        if (empty($this->items)) {
            return null;
        }
        return array_shift($this->items);
    }

    public function front() {
        if (empty($this->items)) {
            return null;
        }
        return $this->items[0];
    }

    public function size(): int {
        return count($this->items);
    }

    public function toArray(): array {
        return $this->items;
    }
}

$queue = new Queue();
$queue->enqueue('first');
$queue->enqueue('second');
$queue->enqueue('third');

echo "\nQueue:\n";
echo "  front: " . $queue->front() . "\n";
echo "  dequeue: " . $queue->dequeue() . "\n";
echo "  dequeue: " . $queue->dequeue() . "\n";
echo "  size: " . $queue->size() . "\n";

// --- priority queue ---

class PriorityQueue {
    private array $items = [];

    public function insert($value, int $priority): void {
        $this->items[] = ['value' => $value, 'priority' => $priority];
        usort($this->items, function($a, $b) {
            return $b['priority'] - $a['priority'];
        });
    }

    public function extract() {
        if (empty($this->items)) {
            return null;
        }
        return array_shift($this->items)['value'];
    }

    public function size(): int {
        return count($this->items);
    }
}

$pq = new PriorityQueue();
$pq->insert('low', 1);
$pq->insert('critical', 10);
$pq->insert('medium', 5);
$pq->insert('high', 8);

echo "\nPriority Queue:\n";
while ($pq->size() > 0) {
    echo "  " . $pq->extract() . "\n";
}

// --- linked list ---

class ListNode {
    public $value;
    public ?ListNode $next;

    public function __construct($value, ?ListNode $next = null) {
        $this->value = $value;
        $this->next = $next;
    }
}

class LinkedList {
    private ?ListNode $head = null;
    private int $length = 0;

    public function prepend($value): void {
        $this->head = new ListNode($value, $this->head);
        $this->length++;
    }

    public function append($value): void {
        $node = new ListNode($value);
        if ($this->head === null) {
            $this->head = $node;
        } else {
            $current = $this->head;
            while ($current->next !== null) {
                $current = $current->next;
            }
            $current->next = $node;
        }
        $this->length++;
    }

    public function removeFirst(): mixed {
        if ($this->head === null) {
            return null;
        }
        $value = $this->head->value;
        $this->head = $this->head->next;
        $this->length--;
        return $value;
    }

    public function contains($value): bool {
        $current = $this->head;
        while ($current !== null) {
            if ($current->value === $value) {
                return true;
            }
            $current = $current->next;
        }
        return false;
    }

    public function size(): int {
        return $this->length;
    }

    public function toArray(): array {
        $result = [];
        $current = $this->head;
        while ($current !== null) {
            $result[] = $current->value;
            $current = $current->next;
        }
        return $result;
    }

    public function reverse(): void {
        $prev = null;
        $current = $this->head;
        while ($current !== null) {
            $next = $current->next;
            $current->next = $prev;
            $prev = $current;
            $current = $next;
        }
        $this->head = $prev;
    }
}

$list = new LinkedList();
$list->append(1);
$list->append(2);
$list->append(3);
$list->prepend(0);

echo "\nLinked List:\n";
echo "  items: " . implode(' -> ', $list->toArray()) . "\n";
echo "  size: " . $list->size() . "\n";
echo "  contains 2: " . ($list->contains(2) ? 'yes' : 'no') . "\n";
echo "  contains 5: " . ($list->contains(5) ? 'yes' : 'no') . "\n";

$list->reverse();
echo "  reversed: " . implode(' -> ', $list->toArray()) . "\n";

echo "  removeFirst: " . $list->removeFirst() . "\n";
echo "  items: " . implode(' -> ', $list->toArray()) . "\n";

// --- ring buffer ---

class RingBuffer {
    private array $buffer;
    private int $capacity;
    private int $head = 0;
    private int $count = 0;

    public function __construct(int $capacity) {
        $this->capacity = $capacity;
        $this->buffer = array_fill(0, $capacity, null);
    }

    public function write($value): void {
        $index = ($this->head + $this->count) % $this->capacity;
        if ($this->count < $this->capacity) {
            $this->count++;
        } else {
            $this->head = ($this->head + 1) % $this->capacity;
        }
        $this->buffer[$index] = $value;
    }

    public function read() {
        if ($this->count === 0) {
            return null;
        }
        $value = $this->buffer[$this->head];
        $this->head = ($this->head + 1) % $this->capacity;
        $this->count--;
        return $value;
    }

    public function size(): int {
        return $this->count;
    }

    public function toArray(): array {
        $result = [];
        for ($i = 0; $i < $this->count; $i++) {
            $result[] = $this->buffer[($this->head + $i) % $this->capacity];
        }
        return $result;
    }
}

$ring = new RingBuffer(3);
$ring->write('a');
$ring->write('b');
$ring->write('c');
echo "\nRing Buffer (cap=3):\n";
echo "  after a,b,c: " . implode(', ', $ring->toArray()) . "\n";

$ring->write('d');
echo "  after d (overflow): " . implode(', ', $ring->toArray()) . "\n";

echo "  read: " . $ring->read() . "\n";
echo "  remaining: " . implode(', ', $ring->toArray()) . "\n";

// --- trie ---

class TrieNode {
    public array $children = [];
    public bool $isEnd = false;
}

class Trie {
    private TrieNode $root;

    public function __construct() {
        $this->root = new TrieNode();
    }

    public function insert(string $word): void {
        $node = $this->root;
        for ($i = 0; $i < strlen($word); $i++) {
            $ch = $word[$i];
            if (!array_key_exists($ch, $node->children)) {
                $node->children[$ch] = new TrieNode();
            }
            $node = $node->children[$ch];
        }
        $node->isEnd = true;
    }

    public function search(string $word): bool {
        $node = $this->findNode($word);
        return $node !== null && $node->isEnd;
    }

    public function startsWith(string $prefix): bool {
        return $this->findNode($prefix) !== null;
    }

    private function findNode(string $str): ?TrieNode {
        $node = $this->root;
        for ($i = 0; $i < strlen($str); $i++) {
            $ch = $str[$i];
            if (!array_key_exists($ch, $node->children)) {
                return null;
            }
            $node = $node->children[$ch];
        }
        return $node;
    }

    public function wordsWithPrefix(string $prefix): array {
        $node = $this->findNode($prefix);
        if ($node === null) {
            return [];
        }
        $words = [];
        $this->collectWords($node, $prefix, $words);
        return $words;
    }

    private function collectWords(TrieNode $node, string $prefix, array &$words): void {
        if ($node->isEnd) {
            $words[] = $prefix;
        }
        ksort($node->children);
        foreach ($node->children as $ch => $child) {
            $this->collectWords($child, $prefix . $ch, $words);
        }
    }
}

$trie = new Trie();
$trie->insert('apple');
$trie->insert('app');
$trie->insert('application');
$trie->insert('apt');
$trie->insert('banana');

echo "\nTrie:\n";
echo "  search 'app': " . ($trie->search('app') ? 'found' : 'not found') . "\n";
echo "  search 'ap': " . ($trie->search('ap') ? 'found' : 'not found') . "\n";
echo "  startsWith 'ap': " . ($trie->startsWith('ap') ? 'yes' : 'no') . "\n";
echo "  words with 'app': " . implode(', ', $trie->wordsWithPrefix('app')) . "\n";
echo "  words with 'b': " . implode(', ', $trie->wordsWithPrefix('b')) . "\n";

// --- array utility functions ---

echo "\nArray utilities:\n";

$data = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];
echo "  original: " . implode(', ', $data) . "\n";
echo "  unique: " . implode(', ', array_values(array_unique($data))) . "\n";
echo "  chunks(3): ";
$chunks = array_chunk($data, 3);
$chunk_strs = [];
foreach ($chunks as $chunk) {
    $chunk_strs[] = '[' . implode(', ', $chunk) . ']';
}
echo implode(', ', $chunk_strs) . "\n";

$spliced = $data;
array_splice($spliced, 2, 3, [100, 200]);
echo "  splice(2,3,[100,200]): " . implode(', ', $spliced) . "\n";
echo "  slice(3,4): " . implode(', ', array_slice($data, 3, 4)) . "\n";
