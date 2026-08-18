#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

#include <cstdio>

int wmain(int argc, wchar_t** argv)
{
    if (argc != 2)
    {
        ::fwprintf(stderr, L"usage: LoadLibraryProbe.exe <dll-path>\n");
        return 2;
    }

    SetLastError(ERROR_SUCCESS);
    HMODULE module = LoadLibraryExW(argv[1], nullptr, DONT_RESOLVE_DLL_REFERENCES);
    if (!module)
    {
        const DWORD error = GetLastError();
        ::fwprintf(stderr, L"LoadLibraryExW failed: %lu (0x%08lX)\n", error, error);
        return 1;
    }

    ::wprintf(L"LoadLibraryExW accepted: %ls\n", argv[1]);
    FreeLibrary(module);
    return 0;
}
