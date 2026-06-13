<?php
// exercises symfony/string grapheme-aware operations (startsWith/endsWith use
// grapheme_extract, previously undefined under zphp). stresses zphp's intl
// grapheme cluster handling end to end
require __DIR__ . '/../app/vendor/autoload.php';

use function Symfony\Component\String\u;

$probes = [
    fn() => var_export(u('Hello')->startsWith('He'), true),
    fn() => var_export(u('Hello')->startsWith('xy'), true),
    fn() => var_export(u('café')->startsWith('caf'), true),
    fn() => var_export(u('über')->endsWith('ber'), true),
    fn() => var_export(u('naïve café')->startsWith('naïve'), true),
    fn() => (string) u('über straße')->upper(),
    fn() => u('a-b-c-d')->afterLast('-')->toString(),
    fn() => u('a-b-c-d')->beforeLast('-')->toString(),
    fn() => u('app/Models/User.php')->afterLast('/')->toString(),
    fn() => (string) u('the quick brown fox')->truncate(9, '…'),
    fn() => u('résumé')->length() . '',
    fn() => u('Hello World')->slice(0, 5)->toString(),
];
foreach ($probes as $i => $p) {
    echo "$i: ", $p(), "\n";
}
