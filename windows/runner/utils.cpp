#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <shellapi.h>
#include <shlobj.h>
#include <cstdio>
#include <iostream>
#include <windows.h>

namespace {

constexpr wchar_t kApplicationKey[] =
    L"Software\\Classes\\Applications\\flsqliteviewer.exe";
constexpr wchar_t kProgId[] = L"FlSQLiteViewer.Database";
constexpr wchar_t kProgIdKey[] = L"Software\\Classes\\FlSQLiteViewer.Database";
constexpr wchar_t kCapabilitiesPath[] =
    L"Software\\Classes\\Applications\\flsqliteviewer.exe\\Capabilities";
constexpr wchar_t kRegisteredApplicationsKey[] =
    L"Software\\RegisteredApplications";

bool SetRegistryString(HKEY root, const wchar_t* key_path,
                       const wchar_t* value_name, const std::wstring& value) {
  HKEY key = nullptr;
  const LONG create_result = ::RegCreateKeyExW(
      root, key_path, 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr,
      &key, nullptr);
  if (create_result != ERROR_SUCCESS) {
    return false;
  }

  const LONG set_result = ::RegSetValueExW(
      key, value_name, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(value.c_str()),
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  ::RegCloseKey(key);
  return set_result == ERROR_SUCCESS;
}

bool SetRegistryEmptyString(HKEY root, const wchar_t* key_path,
                            const wchar_t* value_name) {
  return SetRegistryString(root, key_path, value_name, L"");
}

std::wstring GetExecutablePath() {
  std::wstring path(MAX_PATH, L'\0');
  DWORD length = ::GetModuleFileNameW(nullptr, path.data(),
                                      static_cast<DWORD>(path.size()));
  while (length == path.size()) {
    path.resize(path.size() * 2);
    length = ::GetModuleFileNameW(nullptr, path.data(),
                                  static_cast<DWORD>(path.size()));
  }
  if (length == 0) {
    return L"";
  }
  path.resize(length);
  return path;
}

std::wstring QuoteForCommandLine(const std::wstring& value) {
  return L"\"" + value + L"\"";
}

void RegisterSupportedExtension(const wchar_t* extension) {
  const std::wstring open_with_progids =
      std::wstring(L"Software\\Classes\\") + extension + L"\\OpenWithProgids";
  SetRegistryEmptyString(HKEY_CURRENT_USER, open_with_progids.c_str(), kProgId);

  const std::wstring supported_types =
      std::wstring(kApplicationKey) + L"\\SupportedTypes";
  SetRegistryEmptyString(HKEY_CURRENT_USER, supported_types.c_str(), extension);

  const std::wstring capabilities_associations =
      std::wstring(kCapabilitiesPath) + L"\\FileAssociations";
  SetRegistryString(HKEY_CURRENT_USER, capabilities_associations.c_str(),
                    extension, kProgId);
}

}  // namespace

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE* unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

void RegisterWindowsOpenWithSupport() {
  const std::wstring executable_path = GetExecutablePath();
  if (executable_path.empty()) {
    return;
  }

  const std::wstring quoted_executable = QuoteForCommandLine(executable_path);
  const std::wstring open_command = quoted_executable + L" \"%1\"";
  const std::wstring icon_path = quoted_executable + L",0";

  SetRegistryString(HKEY_CURRENT_USER, kApplicationKey, L"FriendlyAppName",
                    L"FlSQLite Viewer");
  SetRegistryString(HKEY_CURRENT_USER, kApplicationKey, L"FriendlyTypeName",
                    L"SQLite Database");

  SetRegistryString(HKEY_CURRENT_USER, kCapabilitiesPath, L"ApplicationName",
                    L"FlSQLite Viewer");
  SetRegistryString(HKEY_CURRENT_USER, kCapabilitiesPath,
                    L"ApplicationDescription",
                    L"Open SQLite database files with FlSQLite Viewer");
  SetRegistryString(HKEY_CURRENT_USER, kRegisteredApplicationsKey,
                    L"FlSQLite Viewer", kCapabilitiesPath);

  SetRegistryString(HKEY_CURRENT_USER, kProgIdKey, nullptr, L"SQLite Database");
  SetRegistryString(HKEY_CURRENT_USER,
                    L"Software\\Classes\\FlSQLiteViewer.Database\\DefaultIcon",
                    nullptr, icon_path);
  SetRegistryString(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\FlSQLiteViewer.Database\\shell\\open\\command",
      nullptr, open_command);

  SetRegistryString(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Applications\\flsqliteviewer.exe\\shell\\open\\command",
      nullptr, open_command);

  RegisterSupportedExtension(L".db");
  RegisterSupportedExtension(L".sqlite");
  RegisterSupportedExtension(L".sqlite3");

  ::SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
                                   CP_UTF8, WC_ERR_INVALID_CHARS,
                                   utf16_string, -1, nullptr, 0, nullptr,
                                   nullptr) -
                               1;  // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string, input_length,
      utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}