//
//  input_injection.cpp
//  Flutter Host - Windows
//
//  Handles input injection via SendInput API on Windows.
//  Registered as a method channel handler for "app.afkdev.input_injection".
//

#include "input_injection.h"

#include <flutter/encodable_value.h>
#include <windows.h>

#include <cmath>
#include <iostream>
#include <map>
#include <string>

namespace {

// Track mouse button state for drag operations
bool g_isMouseButtonDown = false;
POINT g_lastMousePosition = {0, 0};

// Track active modifier keys
bool g_shiftDown = false;
bool g_ctrlDown = false;
bool g_altDown = false;
bool g_winDown = false;

// Get primary screen dimensions
void GetScreenDimensions(int* width, int* height) {
  *width = GetSystemMetrics(SM_CXSCREEN);
  *height = GetSystemMetrics(SM_CYSCREEN);
}

// Transform normalized coordinates (0-1) to absolute screen coordinates (0-65535)
// SendInput uses absolute coordinates in the range 0-65535
void TransformToAbsoluteCoordinates(double x, double y, int* absX, int* absY) {
  int screenWidth, screenHeight;
  GetScreenDimensions(&screenWidth, &screenHeight);

  // Convert normalized (0-1) to screen pixels
  double screenX = x * screenWidth;
  double screenY = y * screenHeight;

  // Convert to absolute coordinates (0-65535 range)
  *absX = static_cast<int>((screenX / screenWidth) * 65535.0);
  *absY = static_cast<int>((screenY / screenHeight) * 65535.0);
}

// Map X11 keysym codes to Windows virtual key codes
// Standard protocol used by VNC, RDP, and other remote desktop systems
WORD MapX11KeysymToVirtualKey(int keysym) {
  // Modifiers (X11 keysym → Windows VK)
  if (keysym == 0xFFE1) return VK_LSHIFT;    // Shift_L
  if (keysym == 0xFFE3) return VK_LCONTROL;  // Control_L
  if (keysym == 0xFFE9) return VK_LMENU;     // Alt_L (Option)
  if (keysym == 0xFFEB) return VK_LWIN;      // Super_L (Command/Win)

  // Navigation and special keys
  if (keysym == 0xFF09) return VK_TAB;       // Tab
  if (keysym == 0xFF0D) return VK_RETURN;    // Return/Enter
  if (keysym == 0xFF1B) return VK_ESCAPE;    // Escape
  if (keysym == 0x0020) return VK_SPACE;     // Space
  if (keysym == 0xFF08) return VK_BACK;      // BackSpace

  // Arrow keys
  if (keysym == 0xFF51) return VK_LEFT;      // Left
  if (keysym == 0xFF52) return VK_UP;        // Up
  if (keysym == 0xFF53) return VK_RIGHT;     // Right
  if (keysym == 0xFF54) return VK_DOWN;      // Down

  // Function keys
  if (keysym == 0xFFBE) return VK_F1;
  if (keysym == 0xFFBF) return VK_F2;
  if (keysym == 0xFFC0) return VK_F3;
  if (keysym == 0xFFC1) return VK_F4;
  if (keysym == 0xFFC2) return VK_F5;
  if (keysym == 0xFFC3) return VK_F6;
  if (keysym == 0xFFC4) return VK_F7;
  if (keysym == 0xFFC5) return VK_F8;
  if (keysym == 0xFFC6) return VK_F9;
  if (keysym == 0xFFC7) return VK_F10;
  if (keysym == 0xFFC8) return VK_F11;
  if (keysym == 0xFFC9) return VK_F12;

  // Numbers 0-9 (ASCII)
  if (keysym >= 48 && keysym <= 57) return static_cast<WORD>(keysym);  // '0'-'9'

  // Letters a-z (convert to uppercase for VK codes)
  if (keysym >= 97 && keysym <= 122) return static_cast<WORD>(keysym - 32);  // 'a'-'z' → 'A'-'Z'

  // Letters A-Z
  if (keysym >= 65 && keysym <= 90) return static_cast<WORD>(keysym);

  // Common punctuation
  if (keysym == 46) return VK_OEM_PERIOD;    // .
  if (keysym == 44) return VK_OEM_COMMA;     // ,
  if (keysym == 47) return VK_OEM_2;         // /
  if (keysym == 59) return VK_OEM_1;         // ;
  if (keysym == 39) return VK_OEM_7;         // '
  if (keysym == 45) return VK_OEM_MINUS;     // -
  if (keysym == 61) return VK_OEM_PLUS;      // =
  if (keysym == 91) return VK_OEM_4;         // [
  if (keysym == 93) return VK_OEM_6;         // ]
  if (keysym == 92) return VK_OEM_5;         // backslash
  if (keysym == 96) return VK_OEM_3;         // `

  // Shifted symbols - map to base key (shift handled separately)
  if (keysym == 33) return '1';  // !
  if (keysym == 64) return '2';  // @
  if (keysym == 35) return '3';  // #
  if (keysym == 36) return '4';  // $
  if (keysym == 37) return '5';  // %
  if (keysym == 94) return '6';  // ^
  if (keysym == 38) return '7';  // &
  if (keysym == 42) return '8';  // *
  if (keysym == 40) return '9';  // (
  if (keysym == 41) return '0';  // )
  if (keysym == 95) return VK_OEM_MINUS;  // _
  if (keysym == 43) return VK_OEM_PLUS;   // +
  if (keysym == 123) return VK_OEM_4;     // {
  if (keysym == 125) return VK_OEM_6;     // }
  if (keysym == 124) return VK_OEM_5;     // |
  if (keysym == 58) return VK_OEM_1;      // :
  if (keysym == 34) return VK_OEM_7;      // "
  if (keysym == 60) return VK_OEM_COMMA;  // <
  if (keysym == 62) return VK_OEM_PERIOD; // >
  if (keysym == 63) return VK_OEM_2;      // ?
  if (keysym == 126) return VK_OEM_3;     // ~

  // Delete, Home, End, Page Up/Down
  if (keysym == 0xFFFF) return VK_DELETE;
  if (keysym == 0xFF50) return VK_HOME;
  if (keysym == 0xFF57) return VK_END;
  if (keysym == 0xFF55) return VK_PRIOR;  // Page Up
  if (keysym == 0xFF56) return VK_NEXT;   // Page Down

  return 0;  // Unsupported
}

// Check if keysym is a modifier key
bool IsModifierKeysym(int keysym) {
  return keysym == 0xFFE1 ||  // Shift
         keysym == 0xFFE3 ||  // Control
         keysym == 0xFFE9 ||  // Alt
         keysym == 0xFFEB;    // Win/Super
}

// Update modifier state
void UpdateModifierState(int keysym, bool isDown) {
  if (keysym == 0xFFE1) g_shiftDown = isDown;
  else if (keysym == 0xFFE3) g_ctrlDown = isDown;
  else if (keysym == 0xFFE9) g_altDown = isDown;
  else if (keysym == 0xFFEB) g_winDown = isDown;
}

// === Mouse Operations ===

bool HandleMouseMove(double x, double y) {
  int absX, absY;
  TransformToAbsoluteCoordinates(x, y, &absX, &absY);

  INPUT input = {};
  input.type = INPUT_MOUSE;
  input.mi.dx = absX;
  input.mi.dy = absY;
  input.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;

  if (g_isMouseButtonDown) {
    // If button is down, this is a drag
    input.mi.dwFlags |= MOUSEEVENTF_MOVE;
  }

  UINT result = SendInput(1, &input, sizeof(INPUT));

  // Update last position
  int screenWidth, screenHeight;
  GetScreenDimensions(&screenWidth, &screenHeight);
  g_lastMousePosition.x = static_cast<LONG>(x * screenWidth);
  g_lastMousePosition.y = static_cast<LONG>(y * screenHeight);

  return result == 1;
}

bool HandleMouseDown(double x, double y, int button) {
  int absX, absY;
  TransformToAbsoluteCoordinates(x, y, &absX, &absY);

  // First move to position
  INPUT moveInput = {};
  moveInput.type = INPUT_MOUSE;
  moveInput.mi.dx = absX;
  moveInput.mi.dy = absY;
  moveInput.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
  SendInput(1, &moveInput, sizeof(INPUT));

  // Then send button down
  INPUT input = {};
  input.type = INPUT_MOUSE;
  input.mi.dx = absX;
  input.mi.dy = absY;
  input.mi.dwFlags = MOUSEEVENTF_ABSOLUTE;

  if (button == 0) {
    input.mi.dwFlags |= MOUSEEVENTF_LEFTDOWN;
    g_isMouseButtonDown = true;
  } else if (button == 1) {
    input.mi.dwFlags |= MOUSEEVENTF_RIGHTDOWN;
  } else if (button == 2) {
    input.mi.dwFlags |= MOUSEEVENTF_MIDDLEDOWN;
  }

  UINT result = SendInput(1, &input, sizeof(INPUT));
  return result == 1;
}

bool HandleMouseUp(double x, double y, int button) {
  int absX, absY;
  TransformToAbsoluteCoordinates(x, y, &absX, &absY);

  INPUT input = {};
  input.type = INPUT_MOUSE;
  input.mi.dx = absX;
  input.mi.dy = absY;
  input.mi.dwFlags = MOUSEEVENTF_ABSOLUTE;

  if (button == 0) {
    input.mi.dwFlags |= MOUSEEVENTF_LEFTUP;
    g_isMouseButtonDown = false;
  } else if (button == 1) {
    input.mi.dwFlags |= MOUSEEVENTF_RIGHTUP;
  } else if (button == 2) {
    input.mi.dwFlags |= MOUSEEVENTF_MIDDLEUP;
  }

  UINT result = SendInput(1, &input, sizeof(INPUT));
  return result == 1;
}

bool HandleDoubleClick(double x, double y) {
  int absX, absY;
  TransformToAbsoluteCoordinates(x, y, &absX, &absY);

  INPUT inputs[4] = {};

  // First click
  inputs[0].type = INPUT_MOUSE;
  inputs[0].mi.dx = absX;
  inputs[0].mi.dy = absY;
  inputs[0].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_LEFTDOWN;

  inputs[1].type = INPUT_MOUSE;
  inputs[1].mi.dx = absX;
  inputs[1].mi.dy = absY;
  inputs[1].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_LEFTUP;

  // Second click
  inputs[2].type = INPUT_MOUSE;
  inputs[2].mi.dx = absX;
  inputs[2].mi.dy = absY;
  inputs[2].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_LEFTDOWN;

  inputs[3].type = INPUT_MOUSE;
  inputs[3].mi.dx = absX;
  inputs[3].mi.dy = absY;
  inputs[3].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_LEFTUP;

  UINT result = SendInput(4, inputs, sizeof(INPUT));
  return result == 4;
}

bool HandleScroll(double x, double y, double deltaX, double deltaY) {
  int absX, absY;
  TransformToAbsoluteCoordinates(x, y, &absX, &absY);

  // First move to position
  INPUT moveInput = {};
  moveInput.type = INPUT_MOUSE;
  moveInput.mi.dx = absX;
  moveInput.mi.dy = absY;
  moveInput.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
  SendInput(1, &moveInput, sizeof(INPUT));

  bool success = true;

  // Vertical scroll
  // macOS uses pixel-based smooth scrolling, Windows uses notch-based.
  // WHEEL_DELTA (120) = one notch = ~3 lines of text.
  // iOS client sends pixel deltas (typically 1-50 per event).
  // Scale down significantly to match macOS feel: divide by ~40.
  if (std::abs(deltaY) > 0.1) {
    INPUT input = {};
    input.type = INPUT_MOUSE;
    input.mi.dwFlags = MOUSEEVENTF_WHEEL;
    input.mi.mouseData = static_cast<DWORD>(deltaY * 3);
    success = success && (SendInput(1, &input, sizeof(INPUT)) == 1);
  }

  // Horizontal scroll
  if (std::abs(deltaX) > 0.1) {
    INPUT input = {};
    input.type = INPUT_MOUSE;
    input.mi.dwFlags = MOUSEEVENTF_HWHEEL;
    input.mi.mouseData = static_cast<DWORD>(deltaX * 3);
    success = success && (SendInput(1, &input, sizeof(INPUT)) == 1);
  }

  return success;
}

// === Keyboard Operations ===

bool HandleKeyDown(int keysym) {
  WORD vk = MapX11KeysymToVirtualKey(keysym);
  if (vk == 0) {
    std::cerr << "[InputInjection] Unsupported X11 keysym: 0x" << std::hex << keysym << std::endl;
    return false;
  }

  // Update modifier state first
  if (IsModifierKeysym(keysym)) {
    UpdateModifierState(keysym, true);
  }

  INPUT input = {};
  input.type = INPUT_KEYBOARD;
  input.ki.wVk = vk;
  input.ki.wScan = static_cast<WORD>(MapVirtualKey(vk, MAPVK_VK_TO_VSC));
  input.ki.dwFlags = 0;

  UINT result = SendInput(1, &input, sizeof(INPUT));
  return result == 1;
}

bool HandleKeyUp(int keysym) {
  WORD vk = MapX11KeysymToVirtualKey(keysym);
  if (vk == 0) {
    std::cerr << "[InputInjection] Unsupported X11 keysym: 0x" << std::hex << keysym << std::endl;
    return false;
  }

  INPUT input = {};
  input.type = INPUT_KEYBOARD;
  input.ki.wVk = vk;
  input.ki.wScan = static_cast<WORD>(MapVirtualKey(vk, MAPVK_VK_TO_VSC));
  input.ki.dwFlags = KEYEVENTF_KEYUP;

  UINT result = SendInput(1, &input, sizeof(INPUT));

  // Update modifier state after sending
  if (IsModifierKeysym(keysym)) {
    UpdateModifierState(keysym, false);
  }

  return result == 1;
}

bool HandleKeyPress(int keysym, const std::string* character) {
  WORD vk = MapX11KeysymToVirtualKey(keysym);
  if (vk == 0) {
    std::cerr << "[InputInjection] Unsupported X11 keysym: 0x" << std::hex << keysym << std::endl;
    return false;
  }

  INPUT inputs[2] = {};

  // Key down
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = vk;
  inputs[0].ki.wScan = static_cast<WORD>(MapVirtualKey(vk, MAPVK_VK_TO_VSC));
  inputs[0].ki.dwFlags = 0;

  // Key up
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = vk;
  inputs[1].ki.wScan = static_cast<WORD>(MapVirtualKey(vk, MAPVK_VK_TO_VSC));
  inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;

  UINT result = SendInput(2, inputs, sizeof(INPUT));
  return result == 2;
}

bool HandlePasteText(const std::string& text) {
  // Convert UTF-8 to wide string
  int wideLen = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
  if (wideLen <= 0) return false;

  std::wstring wideText(wideLen, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, &wideText[0], wideLen);

  // Copy to clipboard
  if (!OpenClipboard(nullptr)) return false;

  EmptyClipboard();

  size_t size = (wideText.size() + 1) * sizeof(wchar_t);
  HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, size);
  if (!hMem) {
    CloseClipboard();
    return false;
  }

  void* ptr = GlobalLock(hMem);
  if (!ptr) {
    GlobalFree(hMem);
    CloseClipboard();
    return false;
  }

  memcpy(ptr, wideText.c_str(), size);
  GlobalUnlock(hMem);

  SetClipboardData(CF_UNICODETEXT, hMem);
  CloseClipboard();

  // Simulate Ctrl+V
  INPUT inputs[4] = {};

  // Ctrl down
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_CONTROL;
  inputs[0].ki.dwFlags = 0;

  // V down
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = 'V';
  inputs[1].ki.dwFlags = 0;

  // V up
  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = 'V';
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;

  // Ctrl up
  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_CONTROL;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;

  UINT result = SendInput(4, inputs, sizeof(INPUT));
  return result == 4;
}

// Helper to get double from EncodableValue
double GetDouble(const flutter::EncodableValue& value) {
  if (std::holds_alternative<double>(value)) {
    return std::get<double>(value);
  } else if (std::holds_alternative<int32_t>(value)) {
    return static_cast<double>(std::get<int32_t>(value));
  } else if (std::holds_alternative<int64_t>(value)) {
    return static_cast<double>(std::get<int64_t>(value));
  }
  return 0.0;
}

// Helper to get int from EncodableValue
int GetInt(const flutter::EncodableValue& value) {
  if (std::holds_alternative<int32_t>(value)) {
    return std::get<int32_t>(value);
  } else if (std::holds_alternative<int64_t>(value)) {
    return static_cast<int>(std::get<int64_t>(value));
  } else if (std::holds_alternative<double>(value)) {
    return static_cast<int>(std::get<double>(value));
  }
  return 0;
}

// Method channel handler
void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  if (!args) {
    result->Error("INVALID_ARGS", "Expected map arguments");
    return;
  }

  const std::string& method = call.method_name();

  if (method == "mouseMove") {
    auto x_it = args->find(flutter::EncodableValue("x"));
    auto y_it = args->find(flutter::EncodableValue("y"));
    if (x_it == args->end() || y_it == args->end()) {
      result->Error("INVALID_ARGS", "mouseMove requires x, y");
      return;
    }
    bool success = HandleMouseMove(GetDouble(x_it->second), GetDouble(y_it->second));
    result->Success(flutter::EncodableValue(success));

  } else if (method == "mouseDown") {
    auto x_it = args->find(flutter::EncodableValue("x"));
    auto y_it = args->find(flutter::EncodableValue("y"));
    auto button_it = args->find(flutter::EncodableValue("button"));
    if (x_it == args->end() || y_it == args->end() || button_it == args->end()) {
      result->Error("INVALID_ARGS", "mouseDown requires x, y, button");
      return;
    }
    bool success = HandleMouseDown(
        GetDouble(x_it->second),
        GetDouble(y_it->second),
        GetInt(button_it->second));
    result->Success(flutter::EncodableValue(success));

  } else if (method == "mouseUp") {
    auto x_it = args->find(flutter::EncodableValue("x"));
    auto y_it = args->find(flutter::EncodableValue("y"));
    auto button_it = args->find(flutter::EncodableValue("button"));
    if (x_it == args->end() || y_it == args->end() || button_it == args->end()) {
      result->Error("INVALID_ARGS", "mouseUp requires x, y, button");
      return;
    }
    bool success = HandleMouseUp(
        GetDouble(x_it->second),
        GetDouble(y_it->second),
        GetInt(button_it->second));
    result->Success(flutter::EncodableValue(success));

  } else if (method == "doubleClick") {
    auto x_it = args->find(flutter::EncodableValue("x"));
    auto y_it = args->find(flutter::EncodableValue("y"));
    if (x_it == args->end() || y_it == args->end()) {
      result->Error("INVALID_ARGS", "doubleClick requires x, y");
      return;
    }
    bool success = HandleDoubleClick(GetDouble(x_it->second), GetDouble(y_it->second));
    result->Success(flutter::EncodableValue(success));

  } else if (method == "scroll") {
    auto x_it = args->find(flutter::EncodableValue("x"));
    auto y_it = args->find(flutter::EncodableValue("y"));
    auto deltaX_it = args->find(flutter::EncodableValue("deltaX"));
    auto deltaY_it = args->find(flutter::EncodableValue("deltaY"));
    if (x_it == args->end() || y_it == args->end() ||
        deltaX_it == args->end() || deltaY_it == args->end()) {
      result->Error("INVALID_ARGS", "scroll requires x, y, deltaX, deltaY");
      return;
    }
    bool success = HandleScroll(
        GetDouble(x_it->second),
        GetDouble(y_it->second),
        GetDouble(deltaX_it->second),
        GetDouble(deltaY_it->second));
    result->Success(flutter::EncodableValue(success));

  } else if (method == "keyDown") {
    auto keyCode_it = args->find(flutter::EncodableValue("keyCode"));
    if (keyCode_it == args->end()) {
      result->Error("INVALID_ARGS", "keyDown requires keyCode");
      return;
    }
    bool success = HandleKeyDown(GetInt(keyCode_it->second));
    result->Success(flutter::EncodableValue(success));

  } else if (method == "keyUp") {
    auto keyCode_it = args->find(flutter::EncodableValue("keyCode"));
    if (keyCode_it == args->end()) {
      result->Error("INVALID_ARGS", "keyUp requires keyCode");
      return;
    }
    bool success = HandleKeyUp(GetInt(keyCode_it->second));
    result->Success(flutter::EncodableValue(success));

  } else if (method == "keyPress") {
    auto keyCode_it = args->find(flutter::EncodableValue("keyCode"));
    if (keyCode_it == args->end()) {
      result->Error("INVALID_ARGS", "keyPress requires keyCode");
      return;
    }
    auto char_it = args->find(flutter::EncodableValue("character"));
    std::string* charPtr = nullptr;
    std::string charStr;
    if (char_it != args->end() && std::holds_alternative<std::string>(char_it->second)) {
      charStr = std::get<std::string>(char_it->second);
      charPtr = &charStr;
    }
    bool success = HandleKeyPress(GetInt(keyCode_it->second), charPtr);
    result->Success(flutter::EncodableValue(success));

  } else if (method == "pasteText") {
    auto text_it = args->find(flutter::EncodableValue("text"));
    if (text_it == args->end() || !std::holds_alternative<std::string>(text_it->second)) {
      result->Error("INVALID_ARGS", "pasteText requires text");
      return;
    }
    bool success = HandlePasteText(std::get<std::string>(text_it->second));
    result->Success(flutter::EncodableValue(success));

  } else if (method == "checkAccessibility") {
    // Windows doesn't require special accessibility permissions for SendInput
    // when running as the same user
    result->Success(flutter::EncodableValue(true));

  } else if (method == "requestAccessibility") {
    // No-op on Windows
    result->Success();

  } else {
    result->NotImplemented();
  }
}

}  // namespace

void RegisterInputInjectionChannel(flutter::FlutterEngine* engine) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(),
      "app.afkdev.input_injection",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });

  // Note: The channel must be kept alive. In a real plugin, you'd store it.
  // For simplicity, we're using a static channel that lives for the app lifetime.
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> s_channel;
  s_channel = std::move(channel);
}
