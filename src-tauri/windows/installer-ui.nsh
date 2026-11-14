; Native sidebar lettering stays sharp when Windows scales the wizard.
; Header artwork uses four times the base resolution without overlapping controls.
Var SctvTitleFont
Var SctvSmallIcon
Var SctvLargeIcon

!define SCTV_BASE_DPI 96
!define SCTV_IMAGE_ICON 1
!define SCTV_LOAD_ICON_FROM_FILE 0x10
!define SCTV_KEEP_CONTROL_SIZE 0x15
!define SCTV_KEEP_CONTROL_BOUNDS 0x13

!macro SctvGuiFunctions prefix iconPath
  Function ${prefix}SctvGuiInit
    System::Store "S"
    CreateFont $SctvTitleFont "Segoe UI" 16 700

    ; Set both window icon sizes explicitly, including the extracted uninstaller.
    InitPluginsDir
    ; Leave the working directory unchanged so it cannot pin the installation folder.
    File "/oname=$PLUGINSDIR\sctv.ico" "${iconPath}"

    System::Call 'user32::GetDpiForWindow(p $HWNDPARENT) i .r0'
    IntOp $1 $0 * 16
    IntOp $1 $1 / ${SCTV_BASE_DPI}
    IntOp $2 $0 * 32
    IntOp $2 $2 / ${SCTV_BASE_DPI}

    System::Call 'user32::LoadImageW(p 0, w "$PLUGINSDIR\sctv.ico", \
      i ${SCTV_IMAGE_ICON}, i r1, i r1, i ${SCTV_LOAD_ICON_FROM_FILE}) p .r3'
    StrCpy $SctvSmallIcon $3
    SendMessage $HWNDPARENT ${WM_SETICON} 0 $SctvSmallIcon

    System::Call 'user32::LoadImageW(p 0, w "$PLUGINSDIR\sctv.ico", \
      i ${SCTV_IMAGE_ICON}, i r2, i r2, i ${SCTV_LOAD_ICON_FROM_FILE}) p .r3'
    StrCpy $SctvLargeIcon $3
    SendMessage $HWNDPARENT ${WM_SETICON} 1 $SctvLargeIcon

    ; Align the subtitle to the title's actual client position, preserving its size.
    System::Call 'user32::GetWindowRect(p $mui.Header.Text, @r0)'
    System::Call 'user32::MapWindowPoints(p 0, p $HWNDPARENT, p r0, i 2)'
    System::Call '*$0(i .r1)'
    System::Call 'user32::GetWindowRect(p $mui.Header.SubText, @r0)'
    System::Call 'user32::MapWindowPoints(p 0, p $HWNDPARENT, p r0, i 2)'
    System::Call '*$0(i, i .r2)'
    System::Call 'user32::SetWindowPos(p $mui.Header.SubText, \
      p 0, i r1, i r2, i 0, i 0, i ${SCTV_KEEP_CONTROL_SIZE})'

    System::Store "L"
  FunctionEnd

  !if "${prefix}" == ""
    Function .onGUIEnd
  !else
    Function un.onGUIEnd
  !endif
    ; The dialog owns its child controls; this script owns the GDI/icon handles.
    System::Call 'gdi32::DeleteObject(p $SctvTitleFont)'
    System::Call 'user32::DestroyIcon(p $SctvSmallIcon)'
    System::Call 'user32::DestroyIcon(p $SctvLargeIcon)'
  FunctionEnd
!macroend

!insertmacro SctvGuiFunctions "" "${SCTV_WINDOWS_DIR}\..\icons\icon.ico"
!insertmacro SctvGuiFunctions "un." "${SCTV_WINDOWS_DIR}\uninstaller.ico"

Function SctvSidebarShow
  Push $0
  FindWindow $0 "#32770" "" $HWNDPARENT
  GetDlgItem $0 $0 1200
  ${NSD_AddStyle} $0 ${WS_CLIPSIBLINGS}

  ${NSD_CreateLabel} 0u 100u 109u 24u "SCTV DL"
  Pop $0
  ${NSD_AddStyle} $0 ${SS_CENTER}
  SendMessage $0 ${WM_SETFONT} $SctvTitleFont 0
  SetCtlColors $0 "252B30" "F7F2EF"
  System::Call 'user32::SetWindowPos(p r0, p 0, i 0, i 0, i 0, i 0, i ${SCTV_KEEP_CONTROL_BOUNDS})'

  ${NSD_CreateLabel} 0u 125u 109u 16u "电视节目下载"
  Pop $0
  ${NSD_AddStyle} $0 ${SS_CENTER}
  SetCtlColors $0 "737B83" "F7F2EF"
  System::Call 'user32::SetWindowPos(p r0, p 0, i 0, i 0, i 0, i 0, i ${SCTV_KEEP_CONTROL_BOUNDS})'

  Pop $0
FunctionEnd

Function un.SctvConfirmShow
  ; Preserve Tauri's checkbox and leave callback so its state reaches cleanup.
  Call un.ConfirmShow
  System::Store "S"

  System::Call 'user32::GetClientRect(p $mui.UnConfirmPage, @r0)'
  System::Call '*$0(i, i, i .r1, i .r2)'

  System::Call 'user32::GetDpiForWindow(p $mui.UnConfirmPage) i .r3'
  IntOp $4 $3 * 40
  IntOp $4 $4 / ${SCTV_BASE_DPI}
  IntOp $4 $2 - $4
  IntOp $5 $3 * 24
  IntOp $5 $5 / ${SCTV_BASE_DPI}

  System::Call 'user32::MoveWindow(p $DeleteAppDataCheckbox, i 0, i r4, i r1, i r5, i 1)'
  System::Store "L"
FunctionEnd
