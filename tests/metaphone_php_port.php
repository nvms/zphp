<?php
// metaphone as php's metaphone.c computes it
foreach (["Thompson", "aero", "knight", "gnome", "pneumatic", "wright", "white", "water", "xavier", "Schmidt",
          "science", "Christ", "ciao", "edge", "laugh", "sign", "signed", "ghost", "hello", "philosophy",
          "queen", "session", "nation", "thumb", "watch", "box", "yes", "zoo", "  12abc", "", "a\0b",
          "Sccuriiiity", "bbbbb", "ACCCCount"] as $word) {
    var_dump(metaphone($word), metaphone($word, 2));
}
try {
    metaphone("x", -1);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
