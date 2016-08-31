/*
 * slookup.c - static lookup of character sets.
 */

#include "charset.h"
#include "internal.h"

#define ENUM_CHARSET(x) extern charset_spec const charset_##x;
//#include "enum.c"
#undef ENUM_CHARSET

extern const charset_spec *const cs_table[];

/* static charset_spec const *const cs_table[] = { */

#define ENUM_CHARSET(x) &charset_##x,
//#include "enum.c"
#undef ENUM_CHARSET

/* }; */
/*
charset_spec const *charset_find_spec(int charset)
{
    int i;

    for (i = 0; i < (int)lenof(cs_table); i++)
	if (cs_table[i]->charset == charset)
	    return cs_table[i];

    return NULL;
}*/

//extern const int cs_table_size;               // Declare the table size externally

charset_spec const *charset_find_spec(int charset)
{
#if 0
    int i;

    // Use the externally defined cs_table_size instead of lenof
    for (i = 0; i < cs_table_size; i++)
        if (cs_table[i]->charset == charset)
            return cs_table[i];
#endif
    return NULL;
}

