; Keep installer metadata separate from the user's application data choice.
!macro SctvCleanupInstallMetadata
  Push $0
  ${If} $UpdateMode <> 1
    ReadRegStr $0 SHCTX "${MANUPRODUCTKEY}" ""
    ; A previous installation's uninstaller must not erase a newer location.
    ${If} $0 == $INSTDIR
      DeleteRegValue SHCTX "${MANUPRODUCTKEY}" ""
      DeleteRegValue SHCTX "${MANUPRODUCTKEY}" "Installer Language"
      DeleteRegKey /ifempty SHCTX "${MANUPRODUCTKEY}"
      DeleteRegKey /ifempty SHCTX "${MANUKEY}"
    ${EndIf}
  ${EndIf}
  Pop $0
!macroend

Var SctvPreservedData

; Download destinations always contain this application's ownership lock marker.
; Never traverse them or filesystem links, even inside a private profile directory.
!macro SctvDefineDataCleanup prefix
  Function ${prefix}SctvClearPrivateData
    Exch $R0
    Push $R1
    Push $R2
    Push $R3
    IfFileExists "$R0\.sctv-dl.lock" preserve 0
    System::Call 'kernel32::GetFileAttributesW(w R0) i .R3'
    ${If} $R3 = -1
      Goto done
    ${EndIf}
    IntOp $R3 $R3 & 0x400
    ${If} $R3 <> 0
      Goto preserve
    ${EndIf}

    FindFirst $R1 $R2 "$R0\*"
    loop:
      StrCmp $R2 "" finish
      StrCmp $R2 "." next
      StrCmp $R2 ".." next
      System::Call 'kernel32::GetFileAttributesW(w "$R0\$R2") i .R3'
      IntOp $R3 $R3 & 0x10
      ${If} $R3 <> 0
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
      ; Non-recursive removal leaves any preserved destination in place.
      RMDir "$R0"
      IfFileExists "$R0\*" preserve done
    preserve:
      StrCpy $SctvPreservedData 1
    done:
      Pop $R3
      Pop $R2
      Pop $R1
      Pop $R0
  FunctionEnd
!macroend
