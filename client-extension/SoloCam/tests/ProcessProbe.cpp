#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <TlHelp32.h>

#include <cstdio>
#include <cstdint>
#include <cwchar>

namespace
{
void PrintBytes(HANDLE process, std::uintptr_t address, std::size_t count)
{
    unsigned char bytes[64]{};
    SIZE_T read = 0;
    if (count > sizeof(bytes)
        || !ReadProcessMemory(process, reinterpret_cast<const void*>(address), bytes, count, &read))
    {
        ::wprintf(L"ReadProcessMemory(0x%08lX) failed: %lu\n",
            static_cast<unsigned long>(address), GetLastError());
        return;
    }

    ::wprintf(L"0x%08lX:", static_cast<unsigned long>(address));
    for (SIZE_T index = 0; index < read; ++index)
    {
        ::wprintf(L" %02X", bytes[index]);
    }
    ::wprintf(L"\n");
}
}

int wmain(int argc, wchar_t** argv)
{
    if (argc != 2)
    {
        ::fwprintf(stderr, L"usage: ProcessProbe.exe <pid>\n");
        return 2;
    }

    wchar_t* end = nullptr;
    const unsigned long pid = std::wcstoul(argv[1], &end, 10);
    if (!end || *end != L'\0' || pid == 0)
    {
        ::fwprintf(stderr, L"invalid pid: %ls\n", argv[1]);
        return 2;
    }

    HANDLE process = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (!process)
    {
        ::fwprintf(stderr, L"OpenProcess failed: %lu\n", GetLastError());
        return 1;
    }

    PrintBytes(process, 0x0040B7D0, 8);
    PrintBytes(process, 0x004E5CB0, 36);
    PrintBytes(process, 0x009E4270, 32);
    PrintBytes(process, 0x0095F9F0, 8);
    PrintBytes(process, 0x0095FC30, 12);

    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (snapshot == INVALID_HANDLE_VALUE)
    {
        ::fwprintf(stderr, L"CreateToolhelp32Snapshot failed: %lu\n", GetLastError());
        CloseHandle(process);
        return 1;
    }

    MODULEENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    if (!Module32FirstW(snapshot, &entry))
    {
        ::fwprintf(stderr, L"Module32FirstW failed: %lu\n", GetLastError());
        CloseHandle(snapshot);
        CloseHandle(process);
        return 1;
    }

    do
    {
        ::wprintf(L"module: %ls @ %p (%lu bytes)\n",
            entry.szModule, entry.modBaseAddr, entry.modBaseSize);
    } while (Module32NextW(snapshot, &entry));

    CloseHandle(snapshot);
    CloseHandle(process);
    return 0;
}
