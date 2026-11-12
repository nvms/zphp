<?php
// a variable variable named by an integer or a boolean uses its string form,
// and a name that is empty reads an undefined variable

${10} = 42;
var_dump(${10}, ${'10'});
${true} = 'one';
var_dump(${true}, ${'1'});

function scope() {
    $n = 7;
    $$n = 'seven';
    var_dump(${7});
    var_dump(@${''});
}
scope();
