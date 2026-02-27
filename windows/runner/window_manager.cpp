//
//  window_manager.cpp
//  Flutter Host - Windows
//
//  Handles window discovery and manipulation via Win32 APIs on Windows.
//  Registered as a method channel handler for "app.afkdev.window_manager".
//

#include "window_manager.h"

#include <dwmapi.h>
#include <flutter/encodable_value.h>
#include <psapi.h>
#include <shellapi.h>
#include <windows.h>
#include <wincrypt.h>
#include <wincodec.h>

#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

#pragma comment(lib, "dwmapi.lib")

namespace {

// Forward declarations
std::pair<std::vector<uint8_t>, std::string> GetWindowIcon(HWND hwnd);
std::string ComputeSHA256(const std::vector<uint8_t>& data);
RECT GetStreamingMonitorBounds();
bool MoveWindowToStreamingMonitorIfNeeded(HWND hwnd);

// Multi-display support: The HMONITOR of the display currently being streamed.
// Set via setStreamingDisplayId method channel from Dart.
// Defaults to primary monitor if not set.
HMONITOR g_streamingMonitor = MonitorFromWindow(nullptr, MONITOR_DEFAULTTOPRIMARY);

// Convert HWND to string ID
std::string HwndToString(HWND hwnd) {
  std::ostringstream oss;
  oss << reinterpret_cast<uintptr_t>(hwnd);
  return oss.str();
}

// Convert string ID back to HWND
HWND StringToHwnd(const std::string& str) {
  try {
    uintptr_t value = std::stoull(str);
    return reinterpret_cast<HWND>(value);
  } catch (...) {
    return nullptr;
  }
}

// Convert wide string to UTF-8
std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return "";
  int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                  static_cast<int>(wide.size()), nullptr, 0,
                                  nullptr, nullptr);
  std::string result(size, 0);
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()),
                      &result[0], size, nullptr, nullptr);
  return result;
}

// Get window title
std::string GetWindowTitle(HWND hwnd) {
  int length = GetWindowTextLengthW(hwnd);
  if (length == 0) return "";

  std::wstring title(length + 1, L'\0');
  GetWindowTextW(hwnd, &title[0], length + 1);
  title.resize(length);
  return WideToUtf8(title);
}

// Get process executable path
std::string GetProcessExePath(DWORD pid) {
  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return "";

  wchar_t path[MAX_PATH];
  DWORD size = MAX_PATH;
  std::string result;

  if (QueryFullProcessImageNameW(process, 0, path, &size)) {
    result = WideToUtf8(path);
  }

  CloseHandle(process);
  return result;
}

// Extract app name from executable path
std::string GetAppNameFromPath(const std::string& path) {
  if (path.empty()) return "Unknown";

  // Find last backslash
  size_t lastSlash = path.find_last_of("\\/");
  std::string filename =
      (lastSlash != std::string::npos) ? path.substr(lastSlash + 1) : path;

  // Remove .exe extension
  size_t extPos = filename.rfind(".exe");
  if (extPos != std::string::npos) {
    filename = filename.substr(0, extPos);
  }

  return filename;
}

// Check if window should be included in the list
bool ShouldIncludeWindow(HWND hwnd) {
  // Must be visible
  if (!IsWindowVisible(hwnd)) return false;

  // Must have a title
  if (GetWindowTextLengthW(hwnd) == 0) return false;

  // Skip tool windows
  LONG exStyle = GetWindowLongW(hwnd, GWL_EXSTYLE);
  if (exStyle & WS_EX_TOOLWINDOW) return false;

  // Skip windows with an owner (child/popup windows)
  if (GetWindow(hwnd, GW_OWNER) != nullptr) return false;

  // Check if window is cloaked (hidden by DWM, e.g., on other virtual desktop)
  BOOL isCloaked = FALSE;
  DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &isCloaked, sizeof(isCloaked));
  if (isCloaked) return false;

  // Must be a normal app window (has WS_EX_APPWINDOW or no WS_EX_NOACTIVATE)
  // This helps filter out background system windows
  if ((exStyle & WS_EX_NOACTIVATE) && !(exStyle & WS_EX_APPWINDOW))
    return false;

  return true;
}

// Structure to hold window info during enumeration
struct WindowInfo {
  std::string id;
  std::string title;
  std::string appName;
  std::string exePath;
  std::string iconHash;
  RECT bounds;
  DWORD pid;
};

// Callback for EnumWindows
BOOL CALLBACK EnumWindowsCallback(HWND hwnd, LPARAM lParam) {
  auto* windows = reinterpret_cast<std::vector<WindowInfo>*>(lParam);

  if (!ShouldIncludeWindow(hwnd)) return TRUE;

  WindowInfo info;
  info.id = HwndToString(hwnd);
  info.title = GetWindowTitle(hwnd);

  GetWindowThreadProcessId(hwnd, &info.pid);
  info.exePath = GetProcessExePath(info.pid);
  info.appName = GetAppNameFromPath(info.exePath);

  GetWindowRect(hwnd, &info.bounds);

  windows->push_back(info);
  return TRUE;
}

// Discover all windows
std::vector<WindowInfo> DiscoverWindows() {
  std::vector<WindowInfo> windows;
  EnumWindows(EnumWindowsCallback, reinterpret_cast<LPARAM>(&windows));
  return windows;
}

// Cache for icon hashes by exe path (to avoid recomputing for same app)
std::map<std::string, std::string> g_iconHashCache;

// Get icon hash for an exe path (cached)
std::string GetIconHashForExe(const std::string& exePath, HWND hwnd) {
  // Check cache first
  auto it = g_iconHashCache.find(exePath);
  if (it != g_iconHashCache.end()) {
    return it->second;
  }
  
  // Compute icon and hash
  auto [iconData, hash] = GetWindowIcon(hwnd);
  
  // Cache the result (even if empty)
  g_iconHashCache[exePath] = hash;
  
  return hash;
}

// Compute SHA256 hash of data
std::string ComputeSHA256(const std::vector<uint8_t>& data) {
  HCRYPTPROV hProv = 0;
  HCRYPTHASH hHash = 0;
  std::string result;

  if (!CryptAcquireContextW(&hProv, nullptr, nullptr, PROV_RSA_AES,
                            CRYPT_VERIFYCONTEXT)) {
    return "";
  }

  if (!CryptCreateHash(hProv, CALG_SHA_256, 0, 0, &hHash)) {
    CryptReleaseContext(hProv, 0);
    return "";
  }

  if (CryptHashData(hHash, data.data(), static_cast<DWORD>(data.size()), 0)) {
    DWORD hashLen = 32;
    std::vector<BYTE> hash(hashLen);
    if (CryptGetHashParam(hHash, HP_HASHVAL, hash.data(), &hashLen, 0)) {
      std::ostringstream oss;
      for (BYTE b : hash) {
        oss << std::hex << std::setfill('0') << std::setw(2)
            << static_cast<int>(b);
      }
      result = oss.str();
    }
  }

  CryptDestroyHash(hHash);
  CryptReleaseContext(hProv, 0);
  return result;
}

// Convert HICON to PNG data using WIC
std::vector<uint8_t> IconToPng(HICON hIcon) {
  std::vector<uint8_t> pngData;

  // Get icon info
  ICONINFO iconInfo;
  if (!GetIconInfo(hIcon, &iconInfo)) {
    return pngData;
  }

  // Get bitmap info
  BITMAP bmp;
  if (!GetObject(iconInfo.hbmColor ? iconInfo.hbmColor : iconInfo.hbmMask, 
                 sizeof(BITMAP), &bmp)) {
    if (iconInfo.hbmColor) DeleteObject(iconInfo.hbmColor);
    if (iconInfo.hbmMask) DeleteObject(iconInfo.hbmMask);
    return pngData;
  }

  int width = bmp.bmWidth;
  int height = bmp.bmHeight;
  
  // Sanity check
  if (width <= 0 || height <= 0 || width > 256 || height > 256) {
    if (iconInfo.hbmColor) DeleteObject(iconInfo.hbmColor);
    if (iconInfo.hbmMask) DeleteObject(iconInfo.hbmMask);
    return pngData;
  }

  // Create a compatible DC
  HDC hdcScreen = GetDC(nullptr);
  HDC hdcMem = CreateCompatibleDC(hdcScreen);

  // Create a 32-bit DIB section
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = width;
  bmi.bmiHeader.biHeight = -height;  // Top-down (negative = top-down DIB)
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HBITMAP hBitmap = CreateDIBSection(hdcMem, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  
  if (!hBitmap || !bits) {
    DeleteDC(hdcMem);
    ReleaseDC(nullptr, hdcScreen);
    if (iconInfo.hbmColor) DeleteObject(iconInfo.hbmColor);
    if (iconInfo.hbmMask) DeleteObject(iconInfo.hbmMask);
    return pngData;
  }

  HBITMAP hOldBitmap = (HBITMAP)SelectObject(hdcMem, hBitmap);

  // Fill with transparent background
  RECT rc = {0, 0, width, height};
  HBRUSH hBrush = CreateSolidBrush(RGB(0, 0, 0));
  FillRect(hdcMem, &rc, hBrush);
  DeleteObject(hBrush);

  // Draw the icon
  DrawIconEx(hdcMem, 0, 0, hIcon, width, height, 0, nullptr, DI_NORMAL);

  // Initialize COM for WIC (use apartment threading)
  HRESULT hrCom = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  bool comInitialized = SUCCEEDED(hrCom) || hrCom == S_FALSE;

  if (comInitialized) {
    // Create WIC factory
    IWICImagingFactory* pFactory = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&pFactory));

    if (SUCCEEDED(hr) && pFactory) {
      // Create a bitmap from memory
      IWICBitmap* pBitmap = nullptr;
      hr = pFactory->CreateBitmapFromMemory(
          width, height,
          GUID_WICPixelFormat32bppBGRA,
          width * 4,
          width * height * 4,
          static_cast<BYTE*>(bits),
          &pBitmap);

      if (SUCCEEDED(hr) && pBitmap) {
        // Create a stream
        IStream* pStream = nullptr;
        hr = CreateStreamOnHGlobal(nullptr, TRUE, &pStream);

        if (SUCCEEDED(hr) && pStream) {
          // Create PNG encoder
          IWICBitmapEncoder* pEncoder = nullptr;
          hr = pFactory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &pEncoder);

          if (SUCCEEDED(hr) && pEncoder) {
            hr = pEncoder->Initialize(pStream, WICBitmapEncoderNoCache);

            if (SUCCEEDED(hr)) {
              // Create frame
              IWICBitmapFrameEncode* pFrame = nullptr;
              IPropertyBag2* pPropertyBag = nullptr;
              hr = pEncoder->CreateNewFrame(&pFrame, &pPropertyBag);

              if (SUCCEEDED(hr) && pFrame) {
                hr = pFrame->Initialize(pPropertyBag);

                if (SUCCEEDED(hr)) {
                  hr = pFrame->SetSize(width, height);

                  if (SUCCEEDED(hr)) {
                    WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
                    hr = pFrame->SetPixelFormat(&format);

                    if (SUCCEEDED(hr)) {
                      // Write from the WIC bitmap
                      hr = pFrame->WriteSource(pBitmap, nullptr);

                      if (SUCCEEDED(hr)) {
                        hr = pFrame->Commit();

                        if (SUCCEEDED(hr)) {
                          hr = pEncoder->Commit();

                          if (SUCCEEDED(hr)) {
                            // Get the data from the stream
                            LARGE_INTEGER liZero = {};
                            pStream->Seek(liZero, STREAM_SEEK_SET, nullptr);
                            
                            STATSTG stat;
                            if (SUCCEEDED(pStream->Stat(&stat, STATFLAG_NONAME))) {
                              pngData.resize(static_cast<size_t>(stat.cbSize.QuadPart));
                              ULONG bytesRead = 0;
                              pStream->Read(pngData.data(), 
                                           static_cast<ULONG>(pngData.size()), 
                                           &bytesRead);
                              pngData.resize(bytesRead);
                            }
                          }
                        }
                      }
                    }
                  }
                }
                if (pPropertyBag) pPropertyBag->Release();
                pFrame->Release();
              }
            }
            pEncoder->Release();
          }
          pStream->Release();
        }
        pBitmap->Release();
      }
      pFactory->Release();
    }
  }

  // Cleanup
  SelectObject(hdcMem, hOldBitmap);
  DeleteObject(hBitmap);
  DeleteDC(hdcMem);
  ReleaseDC(nullptr, hdcScreen);
  if (iconInfo.hbmColor) DeleteObject(iconInfo.hbmColor);
  if (iconInfo.hbmMask) DeleteObject(iconInfo.hbmMask);

  return pngData;
}

// Get window icon as PNG
std::pair<std::vector<uint8_t>, std::string> GetWindowIcon(HWND hwnd) {
  std::vector<uint8_t> pngData;
  std::string hash;
  HICON hIcon = nullptr;
  bool needToDestroyIcon = false;

  // Method 1: Try to get the window's icon via messages
  hIcon = reinterpret_cast<HICON>(
      SendMessageTimeoutW(hwnd, WM_GETICON, ICON_BIG, 0, 
                          SMTO_ABORTIFHUNG, 100, nullptr));

  if (!hIcon) {
    hIcon = reinterpret_cast<HICON>(
        SendMessageTimeoutW(hwnd, WM_GETICON, ICON_SMALL2, 0,
                            SMTO_ABORTIFHUNG, 100, nullptr));
  }

  if (!hIcon) {
    hIcon = reinterpret_cast<HICON>(
        SendMessageTimeoutW(hwnd, WM_GETICON, ICON_SMALL, 0,
                            SMTO_ABORTIFHUNG, 100, nullptr));
  }

  // Method 2: Get from window class
  if (!hIcon) {
    hIcon = reinterpret_cast<HICON>(
        GetClassLongPtrW(hwnd, GCLP_HICON));
  }

  if (!hIcon) {
    hIcon = reinterpret_cast<HICON>(
        GetClassLongPtrW(hwnd, GCLP_HICONSM));
  }

  // Method 3: Extract from executable using SHGetFileInfo
  if (!hIcon) {
    DWORD pid;
    GetWindowThreadProcessId(hwnd, &pid);
    std::string exePath = GetProcessExePath(pid);
    if (!exePath.empty()) {
      // Convert to wide string properly
      int wideLen = MultiByteToWideChar(CP_UTF8, 0, exePath.c_str(), -1, nullptr, 0);
      std::wstring widePath(wideLen, L'\0');
      MultiByteToWideChar(CP_UTF8, 0, exePath.c_str(), -1, &widePath[0], wideLen);
      
      SHFILEINFOW sfi = {};
      if (SHGetFileInfoW(widePath.c_str(), 0, &sfi, sizeof(sfi), 
                         SHGFI_ICON | SHGFI_LARGEICON)) {
        hIcon = sfi.hIcon;
        needToDestroyIcon = true;
      }
    }
  }

  // Method 4: ExtractIconEx as last resort
  if (!hIcon) {
    DWORD pid;
    GetWindowThreadProcessId(hwnd, &pid);
    std::string exePath = GetProcessExePath(pid);
    if (!exePath.empty()) {
      int wideLen = MultiByteToWideChar(CP_UTF8, 0, exePath.c_str(), -1, nullptr, 0);
      std::wstring widePath(wideLen, L'\0');
      MultiByteToWideChar(CP_UTF8, 0, exePath.c_str(), -1, &widePath[0], wideLen);
      
      HICON hLargeIcon = nullptr;
      if (ExtractIconExW(widePath.c_str(), 0, &hLargeIcon, nullptr, 1) > 0) {
        hIcon = hLargeIcon;
        needToDestroyIcon = true;
      }
    }
  }

  if (hIcon) {
    pngData = IconToPng(hIcon);
    if (!pngData.empty()) {
      hash = ComputeSHA256(pngData);
    }
    
    // Only destroy if we extracted/created the icon
    if (needToDestroyIcon) {
      DestroyIcon(hIcon);
    }
  }

  return {pngData, hash};
}

// Focus a window - with workaround for focus stealing prevention
bool FocusWindow(HWND hwnd) {
  if (!IsWindow(hwnd)) return false;

  // Move window to streaming monitor if it's on a different monitor
  MoveWindowToStreamingMonitorIfNeeded(hwnd);

  // If window is minimized, restore it
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }

  // Get the foreground window's thread
  HWND foregroundHwnd = GetForegroundWindow();
  DWORD foregroundThread = GetWindowThreadProcessId(foregroundHwnd, nullptr);
  DWORD currentThread = GetCurrentThreadId();

  // Attach to the foreground thread to gain focus permission
  bool attached = false;
  if (foregroundThread != currentThread) {
    attached = AttachThreadInput(currentThread, foregroundThread, TRUE);
  }

  // Try to set foreground window
  bool success = false;

  // Method 1: Direct SetForegroundWindow
  if (SetForegroundWindow(hwnd)) {
    success = true;
  }

  // Method 2: BringWindowToTop
  BringWindowToTop(hwnd);

  // Method 3: SetWindowPos with HWND_TOP
  SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);

  // Detach from the foreground thread
  if (attached) {
    AttachThreadInput(currentThread, foregroundThread, FALSE);
  }

  // Verify
  return GetForegroundWindow() == hwnd || success;
}

// Set window bounds (normalized 0-1 coordinates relative to streaming monitor)
bool SetWindowBounds(HWND hwnd, double normX, double normY, double normWidth, double normHeight) {
  if (!IsWindow(hwnd)) return false;

  // A maximized/minimized window ignores explicit bounds. Restore first so
  // SetWindowPos can apply the requested geometry.
  if (IsZoomed(hwnd) || IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }

  // Get streaming monitor dimensions
  RECT monitorBounds = GetStreamingMonitorBounds();
  int monitorWidth = monitorBounds.right - monitorBounds.left;
  int monitorHeight = monitorBounds.bottom - monitorBounds.top;

  // Convert normalized (0-1) coordinates to screen pixels on the streaming monitor
  int x = monitorBounds.left + static_cast<int>(normX * monitorWidth);
  int y = monitorBounds.top + static_cast<int>(normY * monitorHeight);
  int width = static_cast<int>(normWidth * monitorWidth);
  int height = static_cast<int>(normHeight * monitorHeight);

  return SetWindowPos(hwnd, nullptr, x, y, width, height,
                      SWP_NOZORDER | SWP_NOACTIVATE);
}

// Get currently focused window ID
std::string GetFocusedWindowId() {
  HWND hwnd = GetForegroundWindow();
  if (hwnd && ShouldIncludeWindow(hwnd)) {
    return HwndToString(hwnd);
  }
  return "";
}

// Multi-display helpers

// Get the monitor that contains the center of a window
HMONITOR GetMonitorForWindow(HWND hwnd) {
  return MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
}

// Check if a window is on the streaming monitor
bool IsWindowOnStreamingMonitor(HWND hwnd) {
  HMONITOR windowMonitor = GetMonitorForWindow(hwnd);
  if (windowMonitor == g_streamingMonitor) {
    return true;
  }

  // Fallback: compare monitor bounds instead of handles.
  // HMONITOR handles from different sources (e.g. WebRTC source IDs vs
  // MonitorFromWindow) may not match even for the same physical display.
  MONITORINFO windowMi = {};
  windowMi.cbSize = sizeof(MONITORINFO);
  MONITORINFO streamingMi = {};
  streamingMi.cbSize = sizeof(MONITORINFO);
  if (GetMonitorInfoW(windowMonitor, &windowMi) &&
      GetMonitorInfoW(g_streamingMonitor, &streamingMi)) {
    return EqualRect(&windowMi.rcMonitor, &streamingMi.rcMonitor);
  }

  return false;
}

// Get the bounds of the streaming monitor
RECT GetStreamingMonitorBounds() {
  MONITORINFO mi = {};
  mi.cbSize = sizeof(MONITORINFO);
  if (GetMonitorInfoW(g_streamingMonitor, &mi)) {
    return mi.rcWork;  // Use work area (excludes taskbar)
  }
  // Fallback to primary screen
  RECT rc;
  rc.left = 0;
  rc.top = 0;
  rc.right = GetSystemMetrics(SM_CXSCREEN);
  rc.bottom = GetSystemMetrics(SM_CYSCREEN);
  return rc;
}

// Move a window to the center of the streaming monitor if it's on a different monitor
bool MoveWindowToStreamingMonitorIfNeeded(HWND hwnd) {
  if (!IsWindow(hwnd)) return false;

  // Check if already on streaming monitor
  if (IsWindowOnStreamingMonitor(hwnd)) {
    return true;
  }

  // Get current window bounds
  RECT windowRect;
  if (!GetWindowRect(hwnd, &windowRect)) {
    return false;
  }

  int windowWidth = windowRect.right - windowRect.left;
  int windowHeight = windowRect.bottom - windowRect.top;

  // Get streaming monitor bounds
  RECT monitorBounds = GetStreamingMonitorBounds();
  int monitorWidth = monitorBounds.right - monitorBounds.left;
  int monitorHeight = monitorBounds.bottom - monitorBounds.top;

  // Calculate centered position on streaming monitor
  int centeredX = monitorBounds.left + (monitorWidth - windowWidth) / 2;
  int centeredY = monitorBounds.top + (monitorHeight - windowHeight) / 2;

  // Move the window
  bool success = SetWindowPos(hwnd, nullptr, centeredX, centeredY, 0, 0,
                               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);

  if (success) {
    std::cout << "[WindowManager] Moved window to streaming monitor (centered)" << std::endl;
  } else {
    std::cout << "[WindowManager] Failed to move window to streaming monitor" << std::endl;
  }

  return success;
}

// Method channel handler
void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "getWindows") {
    auto windows = DiscoverWindows();
    std::string focusedId = GetFocusedWindowId();

    // Get full streaming monitor bounds for normalizing window coordinates.
    // Use rcMonitor (full bounds) not rcWork (work area) to match macOS CGDisplayBounds
    // and align with the actual video frame which includes the taskbar area.
    MONITORINFO mi = {};
    mi.cbSize = sizeof(MONITORINFO);
    RECT monitorBounds;
    if (GetMonitorInfoW(g_streamingMonitor, &mi)) {
      monitorBounds = mi.rcMonitor;
    } else {
      // Fallback to primary screen
      monitorBounds.left = 0;
      monitorBounds.top = 0;
      monitorBounds.right = GetSystemMetrics(SM_CXSCREEN);
      monitorBounds.bottom = GetSystemMetrics(SM_CYSCREEN);
    }
    double monitorWidth = static_cast<double>(monitorBounds.right - monitorBounds.left);
    double monitorHeight = static_cast<double>(monitorBounds.bottom - monitorBounds.top);

    flutter::EncodableList windowList;
    for (const auto& win : windows) {
      // Get icon hash (cached by exe path)
      HWND hwnd = StringToHwnd(win.id);
      std::string iconHash = GetIconHashForExe(win.exePath, hwnd);

      flutter::EncodableMap windowMap;
      windowMap[flutter::EncodableValue("id")] =
          flutter::EncodableValue(win.id);
      windowMap[flutter::EncodableValue("title")] =
          flutter::EncodableValue(win.title);
      windowMap[flutter::EncodableValue("appName")] =
          flutter::EncodableValue(win.appName);
      // Check if window is on the streaming monitor
      bool onStreamingDisplay = IsWindowOnStreamingMonitor(hwnd);
      windowMap[flutter::EncodableValue("isOnStreamingDisplay")] =
          flutter::EncodableValue(onStreamingDisplay);
      
      // Include iconHash if available
      if (!iconHash.empty()) {
        windowMap[flutter::EncodableValue("iconHash")] =
            flutter::EncodableValue(iconHash);
      }

      // Normalize bounds to 0-1 relative to streaming monitor so the client
      // can map them directly to video coordinates regardless of resolution.
      flutter::EncodableMap boundsMap;
      boundsMap[flutter::EncodableValue("x")] =
          flutter::EncodableValue(monitorWidth > 0
              ? (static_cast<double>(win.bounds.left) - monitorBounds.left) / monitorWidth
              : 0.0);
      boundsMap[flutter::EncodableValue("y")] =
          flutter::EncodableValue(monitorHeight > 0
              ? (static_cast<double>(win.bounds.top) - monitorBounds.top) / monitorHeight
              : 0.0);
      boundsMap[flutter::EncodableValue("width")] =
          flutter::EncodableValue(monitorWidth > 0
              ? static_cast<double>(win.bounds.right - win.bounds.left) / monitorWidth
              : 0.0);
      boundsMap[flutter::EncodableValue("height")] =
          flutter::EncodableValue(monitorHeight > 0
              ? static_cast<double>(win.bounds.bottom - win.bounds.top) / monitorHeight
              : 0.0);
      windowMap[flutter::EncodableValue("bounds")] =
          flutter::EncodableValue(boundsMap);

      windowList.push_back(flutter::EncodableValue(windowMap));
    }

    // Return map with windows array and focusedWindowId (matching macOS format)
    flutter::EncodableMap resultMap;
    resultMap[flutter::EncodableValue("windows")] =
        flutter::EncodableValue(windowList);
    if (!focusedId.empty()) {
      resultMap[flutter::EncodableValue("focusedWindowId")] =
          flutter::EncodableValue(focusedId);
    } else {
      resultMap[flutter::EncodableValue("focusedWindowId")] =
          flutter::EncodableValue();  // null
    }

    result->Success(flutter::EncodableValue(resultMap));
  } else if (method == "focusWindow") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map arguments");
      return;
    }

    auto idIt = args->find(flutter::EncodableValue("id"));
    if (idIt == args->end()) {
      result->Error("INVALID_ARGS", "Missing id");
      return;
    }

    std::string windowId = std::get<std::string>(idIt->second);
    HWND hwnd = StringToHwnd(windowId);

    bool success = FocusWindow(hwnd);
    result->Success(flutter::EncodableValue(success));
  } else if (method == "setWindowBounds") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map arguments");
      return;
    }

    auto idIt = args->find(flutter::EncodableValue("id"));
    auto xIt = args->find(flutter::EncodableValue("x"));
    auto yIt = args->find(flutter::EncodableValue("y"));
    auto widthIt = args->find(flutter::EncodableValue("width"));
    auto heightIt = args->find(flutter::EncodableValue("height"));

    if (idIt == args->end() || xIt == args->end() || yIt == args->end() ||
        widthIt == args->end() || heightIt == args->end()) {
      result->Error("INVALID_ARGS", "Missing required arguments");
      return;
    }

    std::string windowId = std::get<std::string>(idIt->second);
    HWND hwnd = StringToHwnd(windowId);

    // Pass normalized coordinates (0-1) directly - conversion happens in SetWindowBounds
    double x = std::get<double>(xIt->second);
    double y = std::get<double>(yIt->second);
    double width = std::get<double>(widthIt->second);
    double height = std::get<double>(heightIt->second);

    bool success = SetWindowBounds(hwnd, x, y, width, height);
    result->Success(flutter::EncodableValue(success));
  } else if (method == "getWindowIcon") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map arguments");
      return;
    }

    auto idIt = args->find(flutter::EncodableValue("id"));
    if (idIt == args->end()) {
      result->Error("INVALID_ARGS", "Missing id");
      return;
    }

    std::string windowId = std::get<std::string>(idIt->second);
    HWND hwnd = StringToHwnd(windowId);

    auto [iconData, hash] = GetWindowIcon(hwnd);

    flutter::EncodableMap resultMap;
    if (!iconData.empty()) {
      // Convert to base64 to match macOS format
      static const char* base64_chars =
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
      std::string base64;
      base64.reserve(((iconData.size() + 2) / 3) * 4);
      
      for (size_t i = 0; i < iconData.size(); i += 3) {
        uint32_t n = static_cast<uint32_t>(iconData[i]) << 16;
        if (i + 1 < iconData.size()) n |= static_cast<uint32_t>(iconData[i + 1]) << 8;
        if (i + 2 < iconData.size()) n |= static_cast<uint32_t>(iconData[i + 2]);
        
        base64.push_back(base64_chars[(n >> 18) & 0x3F]);
        base64.push_back(base64_chars[(n >> 12) & 0x3F]);
        base64.push_back((i + 1 < iconData.size()) ? base64_chars[(n >> 6) & 0x3F] : '=');
        base64.push_back((i + 2 < iconData.size()) ? base64_chars[n & 0x3F] : '=');
      }
      
      resultMap[flutter::EncodableValue("data")] =
          flutter::EncodableValue(base64);
      resultMap[flutter::EncodableValue("hash")] =
          flutter::EncodableValue(hash);
    }
    result->Success(flutter::EncodableValue(resultMap));
  } else if (method == "checkAccessibility") {
    // Windows doesn't require special accessibility permissions
    result->Success(flutter::EncodableValue(true));
  } else if (method == "requestAccessibility") {
    // No-op on Windows - permissions not needed
    result->Success(flutter::EncodableValue());
  } else if (method == "setStreamingDisplayId") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map arguments");
      return;
    }

    auto displayIdIt = args->find(flutter::EncodableValue("displayId"));
    if (displayIdIt == args->end()) {
      result->Error("INVALID_ARGS", "Missing displayId");
      return;
    }

    int64_t displayId = 0;
    if (std::holds_alternative<int32_t>(displayIdIt->second)) {
      displayId = std::get<int32_t>(displayIdIt->second);
    } else if (std::holds_alternative<int64_t>(displayIdIt->second)) {
      displayId = std::get<int64_t>(displayIdIt->second);
    } else {
      result->Error("INVALID_ARGS", "displayId must be an integer");
      return;
    }

    // The displayId from WebRTC's desktopCapturer may or may not be a valid
    // HMONITOR handle. Try to resolve it to a real monitor:
    // 1. Check if the value directly matches an existing HMONITOR
    // 2. If not, try to use it as a monitor index (0-based)
    // 3. Fall back to the primary monitor
    HMONITOR candidate = reinterpret_cast<HMONITOR>(static_cast<intptr_t>(displayId));
    MONITORINFO mi = {};
    mi.cbSize = sizeof(MONITORINFO);

    if (GetMonitorInfoW(candidate, &mi)) {
      // The displayId is a valid HMONITOR handle
      g_streamingMonitor = candidate;
      std::cout << "[WindowManager] Streaming monitor set to HMONITOR: " << displayId << std::endl;
    } else {
      // Not a valid HMONITOR - try as a monitor index
      struct EnumContext {
        int targetIndex;
        int currentIndex;
        HMONITOR result;
      } ctx = { static_cast<int>(displayId), 0, nullptr };

      EnumDisplayMonitors(nullptr, nullptr,
        [](HMONITOR hMon, HDC, LPRECT, LPARAM lParam) -> BOOL {
          auto* c = reinterpret_cast<EnumContext*>(lParam);
          if (c->currentIndex == c->targetIndex) {
            c->result = hMon;
            return FALSE;  // stop enumerating
          }
          c->currentIndex++;
          return TRUE;
        }, reinterpret_cast<LPARAM>(&ctx));

      if (ctx.result) {
        g_streamingMonitor = ctx.result;
        std::cout << "[WindowManager] Streaming monitor set by index " << displayId
                  << " to HMONITOR: " << reinterpret_cast<intptr_t>(ctx.result) << std::endl;
      } else {
        // Fall back to primary monitor
        g_streamingMonitor = MonitorFromWindow(nullptr, MONITOR_DEFAULTTOPRIMARY);
        std::cout << "[WindowManager] Display ID " << displayId
                  << " not resolved, using primary monitor: "
                  << reinterpret_cast<intptr_t>(g_streamingMonitor) << std::endl;
      }
    }
    result->Success(flutter::EncodableValue());
  } else if (method == "getFocusedWindowId") {
    std::string focusedId = GetFocusedWindowId();
    if (focusedId.empty()) {
      result->Success(flutter::EncodableValue());  // null
    } else {
      result->Success(flutter::EncodableValue(focusedId));
    }
  } else {
    result->NotImplemented();
  }
}

}  // namespace

void RegisterWindowManagerChannel(flutter::FlutterEngine* engine) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "app.afkdev.window_manager",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });
}
