<?php
// covers: interfaces, traits with private properties/methods, class inheritance,
//   method override, instanceof, is_a, get_class, get_parent_class,
//   multiple interface implementation, trait use in classes

interface Renderable
{
    public function render(): string;
}

interface HasTitle
{
    public function getTitle(): string;
}

trait Timestamped
{
    private string $createdAt = "2024-01-01";

    public function getCreatedAt(): string
    {
        return $this->createdAt;
    }

    public function setCreatedAt(string $date): void
    {
        $this->createdAt = $date;
    }
}

class Component implements Renderable
{
    public function getType(): string
    {
        return "component";
    }

    public function render(): string
    {
        return "";
    }

    public function describe(): string
    {
        return $this->getType() . ": " . $this->render();
    }
}

class Heading extends Component implements HasTitle
{
    use Timestamped;

    private string $text;
    private int $level;

    public function __construct(string $text, int $level = 1)
    {
        $this->text = $text;
        $this->level = $level;
    }

    public function getType(): string
    {
        return "heading";
    }

    public function getTitle(): string
    {
        return $this->text;
    }

    public function render(): string
    {
        return "<h" . $this->level . ">" . $this->text . "</h" . $this->level . ">";
    }
}

class Paragraph extends Component
{
    use Timestamped;

    private string $content;

    public function __construct(string $content)
    {
        $this->content = $content;
    }

    public function getType(): string
    {
        return "paragraph";
    }

    public function render(): string
    {
        return "<p>" . $this->content . "</p>";
    }
}

class Page implements Renderable
{
    private string $title;
    private array $components = [];

    public function __construct(string $title)
    {
        $this->title = $title;
    }

    public function add(Component $component): self
    {
        $this->components[] = $component;
        return $this;
    }

    public function render(): string
    {
        $html = "<html><head><title>" . $this->title . "</title></head><body>";
        foreach ($this->components as $c) {
            $html .= $c->render();
        }
        $html .= "</body></html>";
        return $html;
    }

    public function getComponentCount(): int
    {
        return count($this->components);
    }
}

// build a page
$h1 = new Heading("Welcome", 1);
$h1->setCreatedAt("2024-06-15");
$p1 = new Paragraph("This is the first paragraph.");
$p2 = new Paragraph("This is the second paragraph.");
$h2 = new Heading("Section Two", 2);

$page = new Page("My Page");
$page->add($h1)->add($p1)->add($h2)->add($p2);

echo $page->render() . "\n";
echo "components: " . $page->getComponentCount() . "\n";

// test instanceof
echo ($h1 instanceof Renderable) ? "renderable" : "not";
echo "\n";
echo ($h1 instanceof HasTitle) ? "has title" : "no title";
echo "\n";
echo ($p1 instanceof HasTitle) ? "has title" : "no title";
echo "\n";

// test trait
echo $h1->getCreatedAt() . "\n";
echo $p1->getCreatedAt() . "\n";

// test abstract method dispatch
echo $h1->describe() . "\n";
echo $p1->describe() . "\n";

// test is_a
echo is_a($h1, "Component") ? "is component" : "not";
echo "\n";
echo is_a($page, "Component") ? "is component" : "not";
echo "\n";
echo is_a($page, "Renderable") ? "is renderable" : "not";
echo "\n";

// get_class
echo get_class($h1) . "\n";
echo get_class($p1) . "\n";

// get_parent_class
echo get_parent_class($h1) . "\n";

echo "done\n";
