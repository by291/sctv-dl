; Extend Tauri's maintained template instead of copying its install/upgrade logic.
!define SCTV_WINDOWS_DIR "${__FILEDIR__}"
!include "${__FILEDIR__}\installer-cleanup.nsh"

!define MUI_CUSTOMFUNCTION_GUIINIT SctvGuiInit
!define MUI_CUSTOMFUNCTION_UNGUIINIT un.SctvGuiInit
!define MUI_PAGE_CUSTOMFUNCTION_SHOW SctvSidebarShow

; Bind page-specific show callbacks while retaining MUI's page implementations.
; Tauri sets its uninstall callback immediately before this macro, so chain it here.
!macroundef MUI_UNPAGE_CONFIRM
!macro MUI_UNPAGE_CONFIRM
  !define /redef MUI_PAGE_CUSTOMFUNCTION_SHOW un.SctvConfirmShow
  !insertmacro MUI_UNPAGE_INIT
  !insertmacro MUI_PAGEDECLARATION_CONFIRM
!macroend

!macroundef MUI_PAGE_FINISH
!macro MUI_PAGE_FINISH
  !define MUI_PAGE_CUSTOMFUNCTION_SHOW SctvSidebarShow
  !insertmacro MUI_PAGE_INIT
  !insertmacro MUI_PAGEDECLARATION_FINISH
!macroend

!define MUI_WELCOMEPAGE_TITLE "安装 SCTV DL"
!define MUI_WELCOMEPAGE_TEXT "浏览四川电视节目，在线观看或下载整期与精彩片段。$\r$\n$\r$\n点击“下一步”选择安装位置。"
!define MUI_DIRECTORYPAGE_TEXT_TOP "选择应用程序的安装位置。视频保存目录可在应用内单独设置。"
!define MUI_DIRECTORYPAGE_TEXT_DESTINATION "应用安装位置"
!define MUI_FINISHPAGE_TITLE "SCTV DL 安装完成"
!define MUI_FINISHPAGE_TEXT "应用已安装，可以开始浏览、观看和下载节目。$\r$\n$\r$\n点击“完成”关闭安装向导。"
!define MUI_FINISHPAGE_RUN_TEXT "立即启动 SCTV DL"
!define MUI_UNCONFIRMPAGE_TEXT_TOP "将移除应用程序及其快捷方式，已下载的视频会保留。$\r$\n$\r$\n点击“卸载”继续。"
!define MUI_UNCONFIRMPAGE_TEXT_LOCATION "应用安装位置："

Var SctvDeleteAppData
!insertmacro SctvDefineDataCleanup "un."

!macro NSIS_HOOK_PREUNINSTALL
  ; Defer data deletion until Tauri has checked that the application has stopped.
  ; Suppress its recursive profile deletion so nested video destinations survive.
  StrCpy $SctvDeleteAppData $DeleteAppDataCheckboxState
  StrCpy $DeleteAppDataCheckboxState 0
!macroend

!macro NSIS_HOOK_POSTUNINSTALL
  ; Tauri removes this metadata only when the user also deletes their app data.
  ; Remove installation-only values even when preferences and history are kept.
  !insertmacro SctvCleanupInstallMetadata
  ${If} $UpdateMode <> 1
  ${AndIf} $SctvDeleteAppData = 1
    SetShellVarContext current
    Push "$APPDATA\${BUNDLEID}"
    Call un.SctvClearPrivateData
    Push "$LOCALAPPDATA\${BUNDLEID}"
    Call un.SctvClearPrivateData
    ${If} $SctvPreservedData = 1
      DetailPrint "包含下载文件、链接或无法删除的应用数据的目录已保留。"
      IfSilent +2 0
        MessageBox MB_OK|MB_ICONINFORMATION "应用已卸载。包含下载文件、链接或无法删除的应用数据的目录已保留。"
    ${EndIf}
  ${EndIf}
!macroend
