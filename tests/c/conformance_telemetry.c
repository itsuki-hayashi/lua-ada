/* Native process identity only; all managed accounting is measured in Ada. */
#if defined(_WIN32)
#include <process.h>
unsigned long lua_ada_test_process_id(void) { return (unsigned long)_getpid(); }
#else
#include <unistd.h>
unsigned long lua_ada_test_process_id(void) { return (unsigned long)getpid(); }
#endif
