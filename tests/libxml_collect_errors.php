<?php
// regression: libxml_use_internal_errors(true) + libxml_get_errors() actually
// collect parse errors from libxml2 (level/code/line/message/file). previously
// zphp's handlers were stubs that returned empty arrays so frameworks that
// rely on the captured error list (Symfony Yaml-XML loaders, Laravel SVG
// shields, league/html-to-markdown) saw zero diagnostics
libxml_use_internal_errors(true);
$bad = simplexml_load_string('<root><bad attr=value></bad></root>');
$errors = libxml_get_errors();
echo "count: " . count($errors) . "\n";
echo count($errors) > 0 ? "has-errors\n" : "no-errors\n";
foreach ($errors as $e) {
    echo "  level=" . $e->level . " line=" . $e->line . " code>0=" . ($e->code > 0 ? 'y' : 'n') . "\n";
    echo "    msg-nonempty=" . (strlen(trim($e->message)) > 0 ? 'y' : 'n') . "\n";
}

$last = libxml_get_last_error();
echo "last-is-LibXMLError: " . (($last instanceof LibXMLError) ? 'y' : 'n') . "\n";
echo "last-has-msg: " . (strlen(trim($last->message)) > 0 ? 'y' : 'n') . "\n";

libxml_clear_errors();
echo "after-clear: " . count(libxml_get_errors()) . "\n";
var_dump(libxml_get_last_error());

// when use_internal=false, library doesn't push to the captured list (it
// would otherwise spam stderr via libxml's default handler - zphp also
// suppresses that path via xmlSetGenericErrorFunc)
libxml_use_internal_errors(false);
$bad2 = @simplexml_load_string('<broken');
echo "after-off: " . count(libxml_get_errors()) . "\n";
