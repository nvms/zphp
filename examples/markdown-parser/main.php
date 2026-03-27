<?php
// covers: preg_replace, preg_replace_callback, preg_match, preg_match_all, str_repeat, htmlspecialchars, trim, ltrim, str_starts_with, substr, strlen, explode, implode, array_map, array_pop, count

function parseMarkdown(string $markdown): string {
    $lines = explode("\n", $markdown);
    $html = [];
    $inCodeBlock = false;
    $inList = false;
    $listType = '';
    $inBlockquote = false;

    foreach ($lines as $line) {
        // code blocks
        if (str_starts_with(trim($line), '```')) {
            if ($inCodeBlock) {
                $html[] = '</code></pre>';
                $inCodeBlock = false;
            } else {
                $lang = trim(substr(trim($line), 3));
                $html[] = '<pre><code' . ($lang ? ' class="language-' . $lang . '"' : '') . '>';
                $inCodeBlock = true;
            }
            continue;
        }

        if ($inCodeBlock) {
            $html[] = htmlspecialchars($line);
            continue;
        }

        // close list if needed
        if ($inList && !preg_match('/^\s*[-*]\s/', $line) && !preg_match('/^\s*\d+\.\s/', $line) && trim($line) !== '') {
            $html[] = $listType === 'ul' ? '</ul>' : '</ol>';
            $inList = false;
        }

        // close blockquote if needed
        if ($inBlockquote && !str_starts_with($line, '>')) {
            $html[] = '</blockquote>';
            $inBlockquote = false;
        }

        // empty line
        if (trim($line) === '') {
            if ($inList) {
                $html[] = $listType === 'ul' ? '</ul>' : '</ol>';
                $inList = false;
            }
            continue;
        }

        // headings
        if (preg_match('/^(#{1,6})\s+(.+)$/', $line, $matches)) {
            $level = strlen($matches[1]);
            $text = parseInline($matches[2]);
            $html[] = "<h$level>$text</h$level>";
            continue;
        }

        // horizontal rule
        if (preg_match('/^[-*_]{3,}$/', trim($line))) {
            $html[] = '<hr>';
            continue;
        }

        // blockquote
        if (str_starts_with($line, '>')) {
            if (!$inBlockquote) {
                $html[] = '<blockquote>';
                $inBlockquote = true;
            }
            $content = trim(substr($line, 1));
            $html[] = '<p>' . parseInline($content) . '</p>';
            continue;
        }

        // unordered list
        if (preg_match('/^\s*[-*]\s+(.+)$/', $line, $matches)) {
            if (!$inList || $listType !== 'ul') {
                if ($inList) $html[] = '</ol>';
                $html[] = '<ul>';
                $inList = true;
                $listType = 'ul';
            }
            $html[] = '<li>' . parseInline($matches[1]) . '</li>';
            continue;
        }

        // ordered list
        if (preg_match('/^\s*\d+\.\s+(.+)$/', $line, $matches)) {
            if (!$inList || $listType !== 'ol') {
                if ($inList) $html[] = '</ul>';
                $html[] = '<ol>';
                $inList = true;
                $listType = 'ol';
            }
            $html[] = '<li>' . parseInline($matches[1]) . '</li>';
            continue;
        }

        // paragraph
        $html[] = '<p>' . parseInline($line) . '</p>';
    }

    if ($inCodeBlock) $html[] = '</code></pre>';
    if ($inList) $html[] = ($listType === 'ul' ? '</ul>' : '</ol>');
    if ($inBlockquote) $html[] = '</blockquote>';

    return implode("\n", $html);
}

function parseInline(string $text): string {
    // bold + italic
    $text = preg_replace('/\*\*\*(.+?)\*\*\*/', '<strong><em>$1</em></strong>', $text);

    // bold
    $text = preg_replace('/\*\*(.+?)\*\*/', '<strong>$1</strong>', $text);

    // italic
    $text = preg_replace('/\*(.+?)\*/', '<em>$1</em>', $text);

    // inline code
    $text = preg_replace('/`([^`]+)`/', '<code>$1</code>', $text);

    // links
    $text = preg_replace('/\[([^\]]+)\]\(([^)]+)\)/', '<a href="$2">$1</a>', $text);

    // images
    $text = preg_replace('/!\[([^\]]*)\]\(([^)]+)\)/', '<img src="$2" alt="$1">', $text);

    return $text;
}

// --- test ---

$markdown = <<<'MD'
# Markdown Parser

This is a **bold** statement with *italic* and ***bold italic*** text.

## Features

- Headings (h1-h6)
- **Bold** and *italic*
- [Links](https://example.com)
- `inline code`

### Ordered Lists

1. First item
2. Second item
3. Third item

## Code Blocks

```php
function hello() {
    echo "Hello, World!";
}
```

## Blockquotes

> This is a quote.
> It can span multiple lines.

---

## Images

![Alt text](image.png)

That's all, folks!
MD;

$html = parseMarkdown($markdown);
echo $html . "\n";

// --- verify specific patterns ---

echo "\nInline parsing:\n";
$tests = [
    ['**bold**', '<strong>bold</strong>'],
    ['*italic*', '<em>italic</em>'],
    ['***both***', '<strong><em>both</em></strong>'],
    ['`code`', '<code>code</code>'],
    ['[link](url)', '<a href="url">link</a>'],
    ['![img](src)', '<img src="src" alt="img">'],
];

foreach ($tests as $test) {
    $result = parseInline($test[0]);
    $match = $result === $test[1];
    echo "  " . str_pad($test[0], 20) . " -> " . $result . ($match ? '' : ' (EXPECTED: ' . $test[1] . ')') . "\n";
}
