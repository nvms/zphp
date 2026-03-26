<?php
// covers: traits with late static binding (static::), abstract trait methods,
// trait alias (as), enums with methods and interfaces, closures as callbacks,
// compact(), array_map with closures, array_filter, implode, str_replace,
// strtolower, strtoupper, ucfirst, sprintf, array destructuring with skipped
// elements, match expressions, null coalesce (??), spread operator,
// array_key_exists, compact, extract, constructor property promotion,
// ArrayAccess, Countable, protected property access from closure in trait method

// --- trait: renderable ---

trait Renderable {
    abstract protected function renderContent(): string;

    public function render(): string {
        return static::tag() . ': ' . $this->renderContent();
    }
}

trait Escapable {
    public function escape(string $text): string {
        return str_replace(
            ['&', '<', '>', '"'],
            ['&amp;', '&lt;', '&gt;', '&quot;'],
            $text
        );
    }
}

// --- enum: node type ---

enum NodeType: string {
    case Text = 'text';
    case Variable = 'variable';
    case Block = 'block';
    case Comment = 'comment';

    public function isRenderable(): bool {
        return match($this) {
            self::Text, self::Variable, self::Block => true,
            self::Comment => false,
        };
    }

    public function prefix(): string {
        return strtoupper($this->value) . '_';
    }
}

// --- interfaces ---

interface NodeInterface {
    public function getType(): NodeType;
    public function toString(): string;
}

interface ContainerInterface {
    public function addChild(NodeInterface $child): void;
    public function getChildren(): array;
}

// --- base node ---

abstract class Node implements NodeInterface {
    use Renderable;
    use Escapable;

    public function __construct(
        protected string $content
    ) {}

    abstract public static function tag(): string;
}

// --- concrete nodes ---

class TextNode extends Node {
    public function getType(): NodeType {
        return NodeType::Text;
    }

    public static function tag(): string {
        return 'TEXT';
    }

    protected function renderContent(): string {
        return $this->escape($this->content);
    }

    public function toString(): string {
        return $this->render();
    }
}

class VariableNode extends Node {
    public function __construct(
        protected string $content,
        private ?string $filter = null
    ) {
        parent::__construct($content);
    }

    public function getType(): NodeType {
        return NodeType::Variable;
    }

    public static function tag(): string {
        return 'VAR';
    }

    protected function renderContent(): string {
        $name = $this->content;
        $display = $this->filter !== null
            ? sprintf('%s|%s', $name, $this->filter)
            : $name;
        return '{{ ' . $display . ' }}';
    }

    public function toString(): string {
        return $this->render();
    }

    public function getFilter(): ?string {
        return $this->filter;
    }
}

class BlockNode extends Node implements ContainerInterface {
    private array $children = [];

    public function getType(): NodeType {
        return NodeType::Block;
    }

    public static function tag(): string {
        return 'BLOCK';
    }

    public function addChild(NodeInterface $child): void {
        $this->children[] = $child;
    }

    public function getChildren(): array {
        return $this->children;
    }

    protected function renderContent(): string {
        $rendered = array_map(function($child) {
            return $child->toString();
        }, $this->children);
        return implode(' -> ', $rendered);
    }

    public function toString(): string {
        return $this->render();
    }
}

class CommentNode extends Node {
    public function getType(): NodeType {
        return NodeType::Comment;
    }

    public static function tag(): string {
        return 'COMMENT';
    }

    protected function renderContent(): string {
        return '';
    }

    public function toString(): string {
        return '';
    }
}

// --- template context with ArrayAccess ---

class Context implements ArrayAccess, Countable {
    private array $data = [];
    private array $filters = [];

    public function __construct(array $initial = []) {
        $this->data = $initial;
    }

    public function offsetExists(mixed $offset): bool {
        return array_key_exists($offset, $this->data);
    }

    public function offsetGet(mixed $offset): mixed {
        return $this->data[$offset] ?? null;
    }

    public function offsetSet(mixed $offset, mixed $value): void {
        $this->data[$offset] = $value;
    }

    public function offsetUnset(mixed $offset): void {
        unset($this->data[$offset]);
    }

    public function count(): int {
        return count($this->data);
    }

    public function addFilter(string $name, callable $fn): void {
        $this->filters[$name] = $fn;
    }

    public function applyFilter(string $name, string $value): string {
        if (array_key_exists($name, $this->filters)) {
            return ($this->filters[$name])($value);
        }
        return $value;
    }

    public function toArray(): array {
        return $this->data;
    }
}

// --- test node types ---

echo "=== Node Types ===\n";
$text = new TextNode('Hello <world> & "friends"');
echo $text->render() . "\n";
echo "type: " . $text->getType()->value . "\n";
echo "renderable: " . ($text->getType()->isRenderable() ? 'yes' : 'no') . "\n";
echo "prefix: " . $text->getType()->prefix() . "\n";

$var = new VariableNode('user.name', 'upper');
echo $var->render() . "\n";
echo "filter: " . $var->getFilter() . "\n";

$var2 = new VariableNode('title');
echo $var2->render() . "\n";

$comment = new CommentNode('this is hidden');
echo "comment renderable: " . ($comment->getType()->isRenderable() ? 'yes' : 'no') . "\n";
echo "comment output: '" . $comment->toString() . "'\n";

// --- test block with children ---

echo "\n=== Block Structure ===\n";
$block = new BlockNode('main');
$block->addChild(new TextNode('Start'));
$block->addChild(new VariableNode('content'));
$block->addChild(new TextNode('End'));
echo $block->render() . "\n";
echo "children: " . count($block->getChildren()) . "\n";

// --- test context with ArrayAccess ---

echo "\n=== Context ===\n";
$ctx = new Context(['name' => 'Alice', 'age' => 30]);
echo "name: " . $ctx['name'] . "\n";
echo "age: " . $ctx['age'] . "\n";
echo "count: " . count($ctx) . "\n";
echo "exists: " . (isset($ctx['name']) ? 'yes' : 'no') . "\n";
echo "missing: " . (isset($ctx['missing']) ? 'yes' : 'no') . "\n";

$ctx['title'] = 'Engineer';
echo "added: " . $ctx['title'] . "\n";
echo "new count: " . count($ctx) . "\n";

unset($ctx['age']);
echo "after unset: " . count($ctx) . "\n";

// --- filters ---

echo "\n=== Filters ===\n";
$ctx->addFilter('upper', function(string $s): string {
    return strtoupper($s);
});
$ctx->addFilter('lower', function(string $s): string {
    return strtolower($s);
});
$ctx->addFilter('title', function(string $s): string {
    return ucfirst(strtolower($s));
});

echo $ctx->applyFilter('upper', 'hello world') . "\n";
echo $ctx->applyFilter('lower', 'HELLO WORLD') . "\n";
echo $ctx->applyFilter('title', 'hELLO') . "\n";
echo $ctx->applyFilter('unknown', 'passthrough') . "\n";

// --- late static binding ---

echo "\n=== Late Static Binding ===\n";

class Base {
    public static function create(): string {
        return 'created: ' . static::tag();
    }
}

class Child extends Base {
    public static function tag(): string {
        return 'CHILD';
    }
}

echo Child::create() . "\n";
echo TextNode::tag() . "\n";
echo BlockNode::tag() . "\n";

// --- compact/extract ---

echo "\n=== Compact/Extract ===\n";
function buildContext(): array {
    $name = "Bob";
    $role = "admin";
    $level = 5;
    return compact("name", "role", "level");
}

$data = buildContext();
echo "compact: " . $data["name"] . ", " . $data["role"] . ", " . $data["level"] . "\n";

extract($data);
echo "extract: $name, $role, $level\n";

// --- array destructuring with skips ---

echo "\n=== Destructuring ===\n";
$nodes = [new TextNode('a'), new VariableNode('b'), new BlockNode('c')];
[, $second] = $nodes;
echo "skip first: " . $second->render() . "\n";

[$first, , $third] = $nodes;
echo "skip middle: " . $first->render() . ", " . $third->render() . "\n";

// --- enum in match/array context ---

echo "\n=== Enum Operations ===\n";
$types = [NodeType::Text, NodeType::Variable, NodeType::Block, NodeType::Comment];
$renderable = array_filter($types, function(NodeType $t): bool {
    return $t->isRenderable();
});
echo "renderable count: " . count($renderable) . "\n";

$prefixes = array_map(function(NodeType $t): string {
    return $t->prefix();
}, $types);
echo "prefixes: " . implode(', ', $prefixes) . "\n";

// --- spread and defaults ---

echo "\n=== Spread ===\n";
function joinParts(string ...$parts): string {
    return implode(' ', $parts);
}

$words = ['hello', 'beautiful', 'world'];
echo joinParts(...$words) . "\n";

$more = ['one', 'two'];
$combined = [...$words, ...$more];
echo implode(', ', $combined) . "\n";
