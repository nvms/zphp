<?php
declare(encoding='UTF-8');
// with zend.multibyte off a declare(encoding) is ignored with a warning; its
// value must be a literal, which php's parser checks first

foreach (['declare(encoding=M_PI);', 'declare(encoding=[]);', 'declare(encoding="a$b");', 'declare(encoding=1); echo "one\n";', 'declare(encoding="ISO-8859-1", ticks=1); echo "two\n";'] as $code) {
    try {
        eval($code);
    } catch (CompileError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

// and it must be the very first statement
eval('echo "three\n"; declare(encoding="UTF-8");');
