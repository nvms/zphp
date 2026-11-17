<?php
// an internal parameter whose default is an expression of constants prints
// it as written
foreach (['htmlspecialchars', 'html_entity_decode', 'get_html_translation_table', 'stream_socket_server'] as $f) {
    $rf = new ReflectionFunction($f);
    foreach ($rf->getParameters() as $p) {
        if ($p->getName() !== 'flags') continue;
        echo $f, ': ', $p, "\n";
        var_dump($p->getDefaultValue(), $p->isDefaultValueConstant());
    }
}
