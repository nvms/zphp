<?php
// MO file parser - WordPress's bundled gettext message-object reader.
// pure binary parsing, exercises string offsets and unpack().
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';
require_once $abspath . 'wp-includes/pomo/streams.php';
require_once $abspath . 'wp-includes/pomo/po.php';

// build a minimal PO source and parse it
$po_src = <<<'EOT'
msgid ""
msgstr ""
"Project-Id-Version: Test\n"
"Content-Type: text/plain; charset=UTF-8\n"

msgid "Hello"
msgstr "Hola"

msgid "Goodbye"
msgstr "Adios"

msgctxt "noun"
msgid "Run"
msgstr "Carrera"

msgid "%d apple"
msgid_plural "%d apples"
msgstr[0] "%d manzana"
msgstr[1] "%d manzanas"
EOT;

$tmpfile = tempnam(sys_get_temp_dir(), 'pomo_');
file_put_contents($tmpfile, $po_src);

$po = new PO();
$po->import_from_file($tmpfile);

echo 'header-charset-set: ' . (str_contains($po->headers['Content-Type'] ?? '', 'UTF-8') ? 'y' : 'n') . "\n";
echo 'entry-count: ' . count($po->entries) . "\n";

// look up entries
$hello = $po->entries[serialize(['singular' => 'Hello'])] ?? null;
echo 'hello: ' . ($hello ? $hello->translations[0] : 'missing') . "\n";

$ctx = $po->entries[serialize(['singular' => 'Run', 'context' => 'noun'])] ?? null;
echo 'ctx: ' . ($ctx ? $ctx->translations[0] : 'missing') . "\n";

$plural = $po->entries[serialize(['singular' => '%d apple', 'is_plural' => true])] ?? null;
if ($plural) {
    echo "plural-0: " . $plural->translations[0] . "\n";
    echo "plural-1: " . $plural->translations[1] . "\n";
}

@unlink($tmpfile);
if (file_exists($db_path)) unlink($db_path);
