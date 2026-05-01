<?php

// auto-numbered indexed arrays
parse_str('tags[]=a&tags[]=b&tags[]=c', $r1);
print_r($r1);

// explicitly numbered (gaps preserved)
parse_str('items[0]=x&items[2]=z', $r2);
print_r($r2);

// nested associative
parse_str('user[name]=alice&user[age]=30&user[role]=admin', $r3);
print_r($r3);

// deeply nested
parse_str('a[b][c]=1&a[b][d]=2&a[e]=3', $r4);
print_r($r4);

// mixed indexed + assoc
parse_str('x[a][]=1&x[a][]=2&x[b]=q', $r5);
print_r($r5);

// flat key alongside bracketed
parse_str('plain=42&nested[k]=v', $r6);
print_r($r6);

// roundtrip-ish: rebuild query with keys
parse_str('a[1]=x&a[3]=y', $r7);
print_r($r7);
