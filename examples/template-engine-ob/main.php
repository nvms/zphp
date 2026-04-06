<?php
// covers: ob_start, ob_get_clean, ob_end_clean, ob_get_contents, ob_get_level,
//   ob_end_flush, ob_clean, ob_get_length, ob_list_handlers, closures,
//   array_map, implode, compact, named arguments, match expressions

class View {
    private array $sections = [];
    private array $sectionStack = [];
    private $layout = null;
    private array $data = [];

    public function assign(string $key, mixed $value): self {
        $this->data[$key] = $value;
        return $this;
    }

    public function get(string $key, mixed $default = null): mixed {
        return $this->data[$key] ?? $default;
    }

    public function section(string $name): void {
        $this->sectionStack[] = $name;
        ob_start();
    }

    public function endSection(): void {
        $name = array_pop($this->sectionStack);
        $this->sections[$name] = ob_get_clean();
    }

    public function yieldSection(string $name, string $default = ''): string {
        return $this->sections[$name] ?? $default;
    }

    public function extend(callable $layout): void {
        $this->layout = $layout;
    }

    public function render(callable $template): string {
        ob_start();
        $template($this);
        $content = ob_get_clean();

        if ($this->layout !== null) {
            $layoutFn = $this->layout;
            ob_start();
            $layoutFn($this, $content);
            return ob_get_clean();
        }

        return $content;
    }
}

class Component {
    public static function card(string $title, callable $slot): string {
        ob_start();
        echo "<div class=\"card\">\n";
        echo "  <h3>$title</h3>\n";
        echo "  <div class=\"body\">\n";

        ob_start();
        $slot();
        $slotContent = ob_get_clean();
        echo $slotContent;

        echo "  </div>\n";
        echo "</div>\n";
        return ob_get_clean();
    }

    public static function list(array $items, callable $itemRenderer): string {
        ob_start();
        echo "<ul>\n";
        foreach ($items as $item) {
            ob_start();
            $itemRenderer($item);
            $rendered = ob_get_clean();
            echo "  <li>" . trim($rendered) . "</li>\n";
        }
        echo "</ul>\n";
        return ob_get_clean();
    }

    public static function conditional(bool $condition, callable $whenTrue, ?callable $whenFalse = null): string {
        ob_start();
        if ($condition) {
            $whenTrue();
        } elseif ($whenFalse !== null) {
            $whenFalse();
        }
        return ob_get_clean();
    }
}

// layout template
$layout = function(View $view, string $content) {
    echo "<html>\n<head><title>" . $view->yieldSection('title', 'Default') . "</title></head>\n";
    echo "<body>\n";
    echo $view->yieldSection('nav', '<nav>default nav</nav>') . "\n";
    echo "<main>\n$content</main>\n";
    echo $view->yieldSection('footer', '<footer>default</footer>') . "\n";
    echo "</body>\n</html>";
};

// page template
$page = function(View $view) use ($layout) {
    $view->extend($layout);

    $view->section('title');
    echo "Dashboard";
    $view->endSection();

    $view->section('nav');
    echo "<nav>Home | Settings | Logout</nav>";
    $view->endSection();

    $users = $view->get('users', []);
    $showAdmin = $view->get('showAdmin', false);

    echo Component::card("Active Users", function() use ($users) {
        echo Component::list($users, function($user) {
            echo $user['name'] . " (" . $user['role'] . ")";
        });
    });

    echo Component::conditional($showAdmin, function() {
        echo Component::card("Admin Panel", function() {
            echo "  <p>System status: OK</p>\n";
        });
    }, function() {
        echo "  <p>Access denied</p>\n";
    });
};

// render
$view = new View();
$view->assign('users', [
    ['name' => 'Alice', 'role' => 'admin'],
    ['name' => 'Bob', 'role' => 'editor'],
    ['name' => 'Carol', 'role' => 'viewer'],
]);
$view->assign('showAdmin', true);

$html = $view->render($page);
echo $html . "\n";

// demonstrate ob_get_level tracking
echo "\n--- level tracking ---\n";
echo "level: " . ob_get_level() . "\n";
ob_start();
echo "level: " . ob_get_level() . "\n";
ob_start();
echo "level: " . ob_get_level() . "\n";
$inner = ob_get_clean();
$outer = ob_get_clean();
echo "captured inner: " . trim($inner) . "\n";
echo "captured outer: " . trim($outer) . "\n";

// demonstrate ob_get_length
ob_start();
echo "hello";
echo " length: " . ob_get_length();
$r = ob_get_clean();
echo "buffered: " . $r . "\n";

echo "done\n";
