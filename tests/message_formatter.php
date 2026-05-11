<?php
// covers: MessageFormatter (ICU MessageFormat: named/positional args, plural,
// select, number/currency formatting, locale-aware pluralization)

$m = new MessageFormatter('en_US', 'Hello, {name}!');
echo $m->format(['name' => 'World']), "\n";

// plural with English rules (one/other)
$m2 = new MessageFormatter('en_US', '{count, plural, =0{no items} =1{one item} other{# items}}');
echo $m2->format(['count' => 0]), "\n";
echo $m2->format(['count' => 1]), "\n";
echo $m2->format(['count' => 17]), "\n";

// select
$m3 = new MessageFormatter('en_US', '{gender, select, female{She is here} male{He is here} other{They are here}}');
echo $m3->format(['gender' => 'male']), "\n";
echo $m3->format(['gender' => 'female']), "\n";
echo $m3->format(['gender' => 'x']), "\n";

// number, currency
$m4 = new MessageFormatter('en_US', '{n, number, integer} and {p, number, currency}');
echo $m4->format(['n' => 12345.678, 'p' => 99.5]), "\n";

// positional args (no string keys)
$m5 = new MessageFormatter('en_US', '{0} loves {1}.');
echo $m5->format(['Alice', 'PHP']), "\n";

// static helper
echo MessageFormatter::formatMessage('en_US', '{n, plural, =1{one message} other{# messages}}', ['n' => 1]), "\n";
echo MessageFormatter::formatMessage('en_US', '{n, plural, =1{one message} other{# messages}}', ['n' => 5]), "\n";

// French pluralization (different category boundaries)
echo MessageFormatter::formatMessage('fr_FR', '{n, plural, =0{aucun} one{un} other{plusieurs}}', ['n' => 0]), "\n";
echo MessageFormatter::formatMessage('fr_FR', '{n, plural, =0{aucun} one{un} other{plusieurs}}', ['n' => 1]), "\n";
echo MessageFormatter::formatMessage('fr_FR', '{n, plural, =0{aucun} one{un} other{plusieurs}}', ['n' => 2]), "\n";

// getters
echo "pat: ", $m->getPattern(), "\n";
echo "loc: ", $m->getLocale(), "\n";
$m->setPattern('Bye, {x}!');
echo "after set: ", $m->format(['x' => 'now']), "\n";

// procedural
$h = msgfmt_create('en_US', 'Total: {0}');
echo msgfmt_format_message('en_US', 'Total: {0}', [42]), "\n";
