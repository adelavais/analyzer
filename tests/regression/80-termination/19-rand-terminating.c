// PARAM: --set "ana.activated[+]" termination --enable warn.debug --set ana.activated[+] apron --enable ana.int.interval
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main()
{
    // Seed the random number generator
    srand(time(NULL));

    if (rand())
    {
        // Loop inside the if part
        for (int i = 1; i <= 5; i++) // TERM
        {
            printf("Loop inside if part: %d\n", i);
        }
    }
    else
    {
        // Loop inside the else part
        int j = 1;
        while (j <= 5) // TERM
        {
            printf("Loop inside else part: %d\n", j);
            j++;
        }
    }

    return 0;
}
