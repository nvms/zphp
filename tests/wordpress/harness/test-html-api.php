<?php
// WP_HTML_Tag_Processor: WordPress's HTML editing API (introduced 6.2).
// pure PHP, regex + state machines, no DB. used by block themes and gutenberg.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';
require_once $abspath . 'wp-includes/html-api/class-wp-html-attribute-token.php';
require_once $abspath . 'wp-includes/html-api/class-wp-html-span.php';
require_once $abspath . 'wp-includes/html-api/class-wp-html-text-replacement.php';
require_once $abspath . 'wp-includes/html-api/class-wp-html-decoder.php';
require_once $abspath . 'wp-includes/html-api/class-wp-html-token.php';
require_once $abspath . 'wp-includes/html-api/class-wp-html-tag-processor.php';
require_once $abspath . 'wp-includes/kses.php';

$html = '<p class="intro"><a href="https://example.com" rel="noopener">link</a> text</p>';
$p = new WP_HTML_Tag_Processor($html);

$found = 0;
while ($p->next_tag()) {
    $found++;
    echo 'tag: ' . $p->get_tag() . "\n";
    if ($p->get_tag() === 'A') {
        echo 'a-href: ' . $p->get_attribute('href') . "\n";
        echo 'a-rel: ' . $p->get_attribute('rel') . "\n";
    }
    if ($p->get_tag() === 'P') {
        echo 'p-class: ' . $p->get_attribute('class') . "\n";
    }
}
echo "found: $found\n";

// mutation
$p2 = new WP_HTML_Tag_Processor('<a href="old">click</a>');
$p2->next_tag('a');
$p2->set_attribute('href', 'new-url');
$p2->add_class('active');
$p2->remove_attribute('title');
echo 'mutated: ' . $p2->get_updated_html() . "\n";

// attribute query
$p3 = new WP_HTML_Tag_Processor('<div class="foo bar baz" data-id="1"></div>');
$p3->next_tag();
echo 'has-foo: ' . ($p3->has_class('foo') ? 'y' : 'n') . "\n";
echo 'has-quux: ' . ($p3->has_class('quux') ? 'y' : 'n') . "\n";
echo 'attr-data-id: ' . $p3->get_attribute('data-id') . "\n";

// bookmark + back-track
$p4 = new WP_HTML_Tag_Processor('<span>a</span><span>b</span><span>c</span>');
$p4->next_tag();
$p4->set_bookmark('first');
while ($p4->next_tag()) {}
$p4->seek('first');
echo 'after-seek: ' . $p4->get_tag() . "\n";

if (file_exists($db_path)) unlink($db_path);
