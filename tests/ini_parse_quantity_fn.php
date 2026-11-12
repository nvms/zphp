<?php
// ini_parse_quantity() is zend_ini_parse_quantity, warnings included

foreach ([
    '', '  ', '0', '1', '-1', '+5', '128M', '1g', '2K', ' 3 k ', '0x10', '0X1fK', '0o17', '0O7m', '0b101', '0B11k',
    '010', '-0x10', '1mb', '256 then skip a few then g', 'abc', '-', '0x', '0x ', '0x+1', '0b0b1', '0x0b1',
    '0z1', '9223372036854775807', '9223372036854775808', '-9223372036854775808', '-9223372036854775809',
    '8796093022208G', "1\n", "\t2M\t", "1\0k", "1\x7fK", '1e3', '1.5M', '0k', '0g', '00x1',
] as $input) {
    echo json_encode($input), ' => ';
    var_dump(ini_parse_quantity($input));
}
var_dump(ini_parse_quantity(12));
