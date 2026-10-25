#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

// Recommended by NVIDIA to enable high-performance GPU.
extern "C"
{
  __declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
}

// Recommended by AMD to enable high-performance GPU.
extern "C"
{
  __declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
}

HANDLE mutex = NULL;

// Window class name must match the one in win32_window.cpp.
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kTestInstanceEnv[] = L"KAZUMI_TEST_INSTANCE";

// An empty ID uses the original single-instance behavior. For tests, use an
// ASCII identifier such as B. IDs are deliberately restricted so they are
// safe to use in named Windows mutexes.
bool GetTestInstanceId(std::wstring &instance_id)
{
  wchar_t buffer[64] = {};
  const DWORD length = ::GetEnvironmentVariableW(
      kTestInstanceEnv, buffer, sizeof(buffer) / sizeof(buffer[0]));

  if (length >= sizeof(buffer) / sizeof(buffer[0]))
  {
    return false;
  }

  for (DWORD i = 0; i < length; ++i)
  {
    const wchar_t c = buffer[i];
    const bool valid = (c >= L'a' && c <= L'z') ||
                       (c >= L'A' && c <= L'Z') ||
                       (c >= L'0' && c <= L'9') || c == L'_' || c == L'-';
    if (!valid)
    {
      return false;
    }
  }

  instance_id.assign(buffer, length);
  return true;
}

bool ActivateExistingWindow(const std::wstring &window_title)
{
  // In test mode, only activate a window bearing the same test instance ID.
  HWND hwnd = ::FindWindowW(kWindowClassName, window_title.c_str());
  if (hwnd != NULL)
  {
    if (!::IsWindowVisible(hwnd))
    {
      ::ShowWindow(hwnd, SW_SHOW);
    }
    else if (::IsIconic(hwnd))
    {
      ::ShowWindow(hwnd, SW_RESTORE);
    }

    ::SetForegroundWindow(hwnd);

    FLASHWINFO fwi = {0};
    fwi.cbSize = sizeof(FLASHWINFO);
    fwi.hwnd = hwnd;
    fwi.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
    fwi.uCount = 3;
    fwi.dwTimeout = 0;
    ::FlashWindowEx(&fwi);

    return true;
  }
  return false;
}

bool isSingleInstance(const std::wstring &instance_id)
{
  if (mutex != NULL)
  {
    return true;
  }

  std::wstring mutex_str = L"zzclwsx.tomoe.win.mutex";
  if (!instance_id.empty())
  {
    mutex_str += L".";
    mutex_str += instance_id;
  }

  mutex = ::CreateMutexW(NULL, TRUE, mutex_str.c_str());
  if (mutex == NULL)
  {
    return false;
  }

  if (::GetLastError() == ERROR_ALREADY_EXISTS)
  {
    ::CloseHandle(mutex);
    mutex = NULL;
    return false;
  }
  return true;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  std::wstring instance_id;
  if (!GetTestInstanceId(instance_id))
  {
    ::MessageBoxW(NULL,
                  L"KAZUMI_TEST_INSTANCE must contain 1-63 ASCII letters, "
                  L"numbers, '_' or '-'.",
                  L"Tomoe test instance", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }

  std::wstring window_title = L"Tomoe";
  if (!instance_id.empty())
  {
    window_title += L" [test ";
    window_title += instance_id;
    window_title += L"]";
  }

  // The default instance uses this derivative's mutex name. Test instances get
  // distinct mutexes based on KAZUMI_TEST_INSTANCE.
  if (!isSingleInstance(instance_id))
  {
    ActivateExistingWindow(window_title);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // Disable thread merge to improve performance.
  // Attention: This may impact plugin performance and may be incompatible
  // with future Flutter releases.
  project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnSeparateThread);

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(window_title, origin, size))
  {
    if (mutex)
    {
      ::CloseHandle(mutex);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (mutex)
  {
    ::CloseHandle(mutex);
  }
  return EXIT_SUCCESS;
}
