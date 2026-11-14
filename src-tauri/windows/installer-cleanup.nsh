!macro SctvTrimDirectorySeparator path lastCharacter
  StrCpy ${lastCharacter} ${path} 1 -1
  ${If} ${lastCharacter} == "\"
    StrCpy ${path} ${path} -1
  ${EndIf}
!macroend

; Keep installer metadata separate from the user's application data choice.
!macro SctvCleanupInstallMetadata
  Push $0
  Push $1
  Push $2
  ${If} $UpdateMode <> 1
    ReadRegStr $0 SHCTX "${MANUPRODUCTKEY}" ""
    StrCpy $1 $INSTDIR
    ; Tauri may pass the same path with a trailing directory separator.
    !insertmacro SctvTrimDirectorySeparator $0 $2
    !insertmacro SctvTrimDirectorySeparator $1 $2

    ; A previous installation's uninstaller must not erase a newer location.
    ${If} $0 != ""
    ${AndIf} $0 == $1
      DeleteRegValue SHCTX "${MANUPRODUCTKEY}" ""
      DeleteRegValue SHCTX "${MANUPRODUCTKEY}" "Installer Language"
      DeleteRegKey /ifempty SHCTX "${MANUPRODUCTKEY}"
      DeleteRegKey /ifempty SHCTX "${MANUKEY}"
    ${EndIf}
  ${EndIf}
  Pop $2
  Pop $1
  Pop $0
!macroend

Var SctvPreservedData

!define SCTV_INVALID_ATTRIBUTES -1
!define SCTV_DIRECTORY_ATTRIBUTE 0x10
!define SCTV_REPARSE_ATTRIBUTE 0x400
!define SCTV_FILE_NOT_FOUND 2
!define SCTV_PATH_NOT_FOUND 3

; Leave the Win32 error code available before an NSIS command can overwrite it.
!macro SctvReadCleanupAttributes path
  System::Call 'kernel32::GetFileAttributesW(w "${path}") i .R3 ?e'
  Pop $R4
!macroend

!macro SctvOnMissingPath target
  ${If} $R4 = ${SCTV_FILE_NOT_FOUND}
  ${OrIf} $R4 = ${SCTV_PATH_NOT_FOUND}
    Goto ${target}
  ${EndIf}
!macroend

; Download destinations always contain this application's ownership lock marker.
; Never traverse them or filesystem links, even inside a private profile directory.
!macro SctvDefineDataCleanup prefix
  Function ${prefix}SctvClearPrivateData
    Exch $R0
    Push $R1
    Push $R2
    Push $R3
    Push $R4

    ; A failed probe is safe to ignore only when Windows confirms absence.
    !insertmacro SctvReadCleanupAttributes "$R0"
    ${If} $R3 = ${SCTV_INVALID_ATTRIBUTES}
      !insertmacro SctvOnMissingPath done
      Goto preserve
    ${EndIf}
    IntOp $R4 $R3 & ${SCTV_REPARSE_ATTRIBUTE}
    IntOp $R3 $R3 & ${SCTV_DIRECTORY_ATTRIBUTE}
    ${If} $R4 <> 0
    ${OrIf} $R3 = 0
      Goto preserve
    ${EndIf}

    ; Only inspect the marker after rejecting links and preserve on unreadable markers.
    !insertmacro SctvReadCleanupAttributes "$R0\.sctv-dl.lock"
    ${If} $R3 <> ${SCTV_INVALID_ATTRIBUTES}
      Goto preserve
    ${EndIf}
    !insertmacro SctvOnMissingPath enumerate
    Goto preserve

    enumerate:
    FindFirst $R1 $R2 "$R0\*"
    StrCmp $R1 "" remove_root
    loop:
      StrCmp $R2 "" finish
      StrCmp $R2 "." next
      StrCmp $R2 ".." next

      !insertmacro SctvReadCleanupAttributes "$R0\$R2"
      ${If} $R3 = ${SCTV_INVALID_ATTRIBUTES}
        !insertmacro SctvOnMissingPath next
        StrCpy $SctvPreservedData 1
        Goto next
      ${EndIf}

      IntOp $R4 $R3 & ${SCTV_REPARSE_ATTRIBUTE}
      IntOp $R3 $R3 & ${SCTV_DIRECTORY_ATTRIBUTE}
      ${If} $R4 <> 0
        StrCpy $SctvPreservedData 1
      ${ElseIf} $R3 <> 0
        Push "$R0\$R2"
        Call ${prefix}SctvClearPrivateData
      ${Else}
        Delete "$R0\$R2"
      ${EndIf}
    next:
      FindNext $R1 $R2
      Goto loop
    finish:
      FindClose $R1

    remove_root:
      ; Non-recursive removal proves cleanup without relying on another directory listing.
      System::Call 'kernel32::RemoveDirectoryW(w R0) i .R3 ?e'
      Pop $R4
      ${If} $R3 <> 0
        Goto done
      ${EndIf}
      !insertmacro SctvOnMissingPath done
    preserve:
      StrCpy $SctvPreservedData 1
    done:
      Pop $R4
      Pop $R3
      Pop $R2
      Pop $R1
      Pop $R0
  FunctionEnd
!macroend
