<?php
// a heredoc's closing marker sets how much indentation every body line
// loses; php rejects a body line with less, and tabs mixed with spaces

$cases = [
    'body too shallow' => "return <<<END\n  a\n b\n  END;",
    'tabs and spaces in body' => "return <<<END\n\t\ta\n \tb\n\t\tEND;",
    'mixed closing marker' => "return <<<END\n\t a\n\t END;",
    'nowdoc too shallow' => "return <<<'END'\n    x\n  y\n    END;",
    'blank line is fine' => "return <<<END\n    a\n\n    b\n    END;",
    'whitespace-only short line is fine' => "return <<<END\n    a\n  \n    b\n    END;",
    'unindented' => "return <<<END\na\nEND;",
];
foreach ($cases as $label => $code) {
    try {
        var_dump(eval($code));
    } catch (ParseError $e) {
        echo "$label: ", $e->getMessage(), " (line ", $e->getLine(), ")\n";
    }
}
