<?php
// nl_langinfo reads the c library's locale data for the items php registers
setlocale(LC_ALL, 'C');
var_dump(nl_langinfo(ABDAY_2), nl_langinfo(DAY_4), nl_langinfo(ABMON_7), nl_langinfo(MON_4));
var_dump(nl_langinfo(RADIXCHAR), nl_langinfo(THOUSEP), nl_langinfo(CODESET));
var_dump(nl_langinfo(D_T_FMT), nl_langinfo(AM_STR), nl_langinfo(YESEXPR));
var_dump(DECIMAL_POINT === RADIXCHAR, ABDAY_1, CODESET);
var_dump(nl_langinfo(-1));
var_dump(nl_langinfo(12345678));
