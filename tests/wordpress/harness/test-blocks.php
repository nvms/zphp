<?php
// block parser: WP_Block_Parser parses Gutenberg block markup into a tree.
// pure PHP, exercises stateful tokenizer + recursive parsing.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';
require_once $abspath . 'wp-includes/class-wp-block-parser.php';
require_once $abspath . 'wp-includes/class-wp-block-parser-block.php';
require_once $abspath . 'wp-includes/class-wp-block-parser-frame.php';
require_once $abspath . 'wp-includes/blocks.php';

$markup = '<!-- wp:paragraph {"align":"center"} -->
<p class="has-text-align-center">Hello world</p>
<!-- /wp:paragraph -->

<!-- wp:list -->
<ul>
<!-- wp:list-item -->
<li>one</li>
<!-- /wp:list-item -->
<!-- wp:list-item -->
<li>two</li>
<!-- /wp:list-item -->
</ul>
<!-- /wp:list -->

<!-- wp:html -->
<div>raw html</div>
<!-- /wp:html -->';

$blocks = parse_blocks($markup);

// filter empty / whitespace-only top-level entries
$named = array_values(array_filter($blocks, fn($b) => $b['blockName'] !== null));
echo 'count: ' . count($named) . "\n";
foreach ($named as $i => $b) {
    echo "block-$i.name: " . $b['blockName'] . "\n";
    echo "block-$i.attrs: " . json_encode($b['attrs']) . "\n";
    echo "block-$i.inner-blocks: " . count($b['innerBlocks']) . "\n";
}

// list block (index 1) has 2 inner items
$list = $named[1];
foreach ($list['innerBlocks'] as $j => $item) {
    echo "list-item-$j: " . trim($item['innerHTML']) . "\n";
}

// parse_blocks helper
$simple = parse_blocks('<!-- wp:heading -->
<h2>Title</h2>
<!-- /wp:heading -->');
echo 'simple-count: ' . count($simple) . "\n";
echo 'simple-name: ' . $simple[0]['blockName'] . "\n";

// has_blocks / has_block
echo 'has: ' . (has_blocks($markup) ? 'y' : 'n') . "\n";
echo 'has-para: ' . (has_block('core/paragraph', $markup) ? 'y' : 'n') . "\n";
echo 'has-image: ' . (has_block('core/image', $markup) ? 'y' : 'n') . "\n";

// serialize roundtrip - need WP_Block_Parser_Block objects for that
$parser = new WP_Block_Parser();
$objs = $parser->parse($markup);
$serialized = serialize_blocks($objs);
echo 'serialize-non-empty: ' . (strlen($serialized) > 50 ? 'y' : 'n') . "\n";

if (file_exists($db_path)) unlink($db_path);
