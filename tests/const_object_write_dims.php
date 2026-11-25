<?php
const E = [];
const N = null;
const F = false;
const S = "abc";
const I = 5;
const L = [[1], 'o' => [new stdClass]];
const AO = new ArrayObject(['k' => new stdClass]);

function attempt(string $label, callable $f): void {
    try {
        $f();
        echo "$label: ok\n";
    } catch (Throwable $e) {
        echo "$label: ", $e::class, ': ', $e->getMessage(), "\n";
    }
}

attempt('E[5]', fn() => E[5]->x = 1);
attempt('E[]', function () { E[]->x = 1; });
attempt('E[1][2]', fn() => E[1][2]->x = 1);
attempt('N[0]', fn() => N[0]->x = 1);
attempt('F[0]', fn() => F[0]->x = 1);
attempt('S[0]', fn() => S[0]->x = 1);
attempt('I[0]', fn() => I[0]->x = 1);
attempt('L[0][1]', fn() => L[0][1]->x = 1);
attempt('L[0][0]', fn() => L[0][0]->x = 1);
attempt('L[[]]', fn() => L[[]]->x = 1);
attempt('L[null]', fn() => L[null]->x = 1);
attempt('L[o][0]', fn() => L['o'][0]->x = 1);
attempt('L[o][0] inc', fn() => L['o'][0]->n = (L['o'][0]->n ?? 0) + 1);
attempt('L[o][0]++', function () { L['o'][0]->n++; });
attempt('L[o][5]++', function () { L['o'][5]->n++; });
attempt('L[o][0] .=', function () { L['o'][0]->s = 'a'; L['o'][0]->s .= 'b'; });
attempt('AO[k]', fn() => AO['k']->x = 'via offsetGet');
var_dump(E, N, F, L, AO['k']);

function inner() {
    L['o'][0]->fromFunction = true;
    E[9]->x = 1;
}
attempt('inner', 'inner');
var_dump(L['o'][0]->fromFunction, E, array_keys(get_defined_vars()));

const O = new stdClass;
const A = [];
class CC { const O = O; }
(O)->g = 1;
var_dump(O->g);
CC::{'O'}->dyn = 2;
var_dump(O->dyn);
try { A[5]->x = 1; } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { A[]->x = 1; } catch (Error $e) { echo $e->getMessage(), "\n"; }
$r = &O->ref;
$r = 5;
var_dump(O->ref);
\O->ns = 3;
var_dump(O->ns);
O->{'dy' . 'n2'} = 4;
var_dump(O->dyn2);
O->arr['k'][] = 1;
var_dump(O->arr);
foreach ([1, 2] as O->it) {}
var_dump(O->it);
