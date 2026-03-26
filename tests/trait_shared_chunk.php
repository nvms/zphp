<?php
// tests that trait methods shared across multiple classes don't cause
// visibility confusion when closures access private properties

trait Cacheable {
    private array $cache = [];
    public function cached(string $key, callable $compute): string {
        if (!array_key_exists($key, $this->cache)) {
            $this->cache[$key] = $compute();
        }
        return $this->cache[$key];
    }
}

trait Renderable {
    abstract protected function renderContent(): string;
    public function render(): string {
        return static::tag() . ': ' . $this->renderContent();
    }
}

trait Escapable {
    public function escape(string $text): string {
        return str_replace(['<', '>'], ['&lt;', '&gt;'], $text);
    }
}

abstract class Node {
    use Renderable;
    use Escapable;
    public function __construct(protected string $content) {}
    abstract public static function tag(): string;
}

class TextNode extends Node {
    use Cacheable;
    public static function tag(): string { return 'TEXT'; }
    protected function renderContent(): string {
        return $this->cached('render', function() {
            return $this->escape($this->content);
        });
    }
    public function toString(): string { return $this->render(); }
}

class VarNode extends Node {
    private ?string $filter;
    public function __construct(string $content, ?string $filter = null) {
        parent::__construct($content);
        $this->filter = $filter;
    }
    public static function tag(): string { return 'VAR'; }
    protected function renderContent(): string { return $this->content; }
    public function toString(): string { return $this->render(); }
}

class BlockNode extends Node {
    use Cacheable;
    private array $children = [];
    public static function tag(): string { return 'BLOCK'; }
    public function addChild($child): void { $this->children[] = $child; }
    protected function renderContent(): string {
        return $this->cached('children', function() {
            $rendered = array_map(function($child) {
                return $child->toString();
            }, $this->children);
            return implode(' -> ', $rendered);
        });
    }
    public function toString(): string { return $this->render(); }
}

// single trait user
$text = new TextNode('hello <world>');
echo $text->render() . "\n";

// multiple trait users with nested closures and array_map
$block = new BlockNode('main');
$block->addChild(new TextNode('Start'));
$block->addChild(new VarNode('content'));
$block->addChild(new TextNode('End'));
echo $block->render() . "\n";

// cache hit path
echo $block->render() . "\n";
