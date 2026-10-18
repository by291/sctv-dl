Unicode true
SilentInstall silent
RequestExecutionLevel user
!include LogicLib.nsh
!include "..\installer-cleanup.nsh"
!define MANUKEY "Software\SctvInstallerTests\${TEST_ID}"
!define MANUPRODUCTKEY "${MANUKEY}\Product"
OutFile "${TEST_OUTPUT}\cleanup-check.exe"
Var UpdateMode
!insertmacro SctvDefineDataCleanup ""

!macro WriteFixture path
  FileOpen $7 "${path}" w
  FileWrite $7 "fixture"
  FileClose $7
!macroend

!macro AssertPath path expected
  IfFileExists "${path}" 0 +3
    StrCpy $1 "present"
    Goto +2
  StrCpy $1 "absent"
  ${If} $1 != "${expected}"
    FileWrite $9 "FAIL: ${path}: expected ${expected}, received $1$\r$\n"
    SetErrorLevel 1
    Goto done
  ${EndIf}
!macroend

!macro AssertValue name expected
  ReadRegStr $1 HKCU "${MANUPRODUCTKEY}" "${name}"
  ${If} $1 != "${expected}"
    FileWrite $9 "FAIL: ${name}: expected '${expected}', received '$1'$\r$\n"
    SetErrorLevel 1
    Goto done
  ${EndIf}
!macroend

Section
  SetShellVarContext current
  SetRegView 64
  StrCpy $INSTDIR "$EXEDIR\app"
  FileOpen $9 "$EXEDIR\cleanup-result.txt" w

  ; Removing an installation must not require deleting application data.
  StrCpy $UpdateMode 0
  WriteRegStr HKCU "${MANUPRODUCTKEY}" "" "$INSTDIR"
  WriteRegStr HKCU "${MANUPRODUCTKEY}" "Installer Language" "2052"
  WriteRegStr HKCU "${MANUPRODUCTKEY}" "OtherValue" "preserved"
  !insertmacro SctvCleanupInstallMetadata
  !insertmacro AssertValue "" ""
  !insertmacro AssertValue "Installer Language" ""
  !insertmacro AssertValue "OtherValue" "preserved"

  ; NSIS can provide the uninstall directory with a trailing separator.
  WriteRegStr HKCU "${MANUPRODUCTKEY}" "" "$INSTDIR"
  WriteRegStr HKCU "${MANUPRODUCTKEY}" "Installer Language" "2052"
  StrCpy $INSTDIR "$INSTDIR\"
  !insertmacro SctvCleanupInstallMetadata
  !insertmacro AssertValue "" ""
  !insertmacro AssertValue "Installer Language" ""

  ; Upgrade uninstalls retain the existing install location and language.
  StrCpy $UpdateMode 1
  WriteRegStr HKCU "${MANUPRODUCTKEY}" "" "$INSTDIR"
  WriteRegStr HKCU "${MANUPRODUCTKEY}" "Installer Language" "2052"
  !insertmacro SctvCleanupInstallMetadata
  !insertmacro AssertValue "" "$INSTDIR"
  !insertmacro AssertValue "Installer Language" "2052"

  ; A stale uninstaller cannot remove another installation's registration.
  StrCpy $UpdateMode 0
  WriteRegStr HKCU "${MANUPRODUCTKEY}" "" "$EXEDIR\other-app"
  !insertmacro SctvCleanupInstallMetadata
  !insertmacro AssertValue "" "$EXEDIR\other-app"
  !insertmacro AssertValue "Installer Language" "2052"

  ; Empty product and manufacturer keys disappear after a normal uninstall.
  WriteRegStr HKCU "${MANUPRODUCTKEY}" "" "$INSTDIR"
  DeleteRegValue HKCU "${MANUPRODUCTKEY}" "OtherValue"
  !insertmacro SctvCleanupInstallMetadata
  ClearErrors
  EnumRegKey $1 HKCU "${MANUKEY}" 0
  ${IfNot} ${Errors}
    FileWrite $9 "FAIL: empty product key remains$\r$\n"
    SetErrorLevel 1
    Goto done
  ${EndIf}
  ; Clearing private data preserves downloads even inside the private tree.
  CreateDirectory "$EXEDIR\profile\programme-cache"
  CreateDirectory "$EXEDIR\profile\videos"
  CreateDirectory "$EXEDIR\external-videos"
  !insertmacro WriteFixture "$EXEDIR\profile\desktop.json"
  !insertmacro WriteFixture "$EXEDIR\profile\programme-cache\manifest.json"
  !insertmacro WriteFixture "$EXEDIR\profile\videos\.sctv-dl.lock"
  !insertmacro WriteFixture "$EXEDIR\profile\videos\episode.mp4"
  !insertmacro WriteFixture "$EXEDIR\profile\videos\unfinished.part"
  !insertmacro WriteFixture "$EXEDIR\external-videos\episode.mp4"
  Push "$EXEDIR\profile"
  Call SctvClearPrivateData
  !insertmacro AssertPath "$EXEDIR\profile\desktop.json" "absent"
  !insertmacro AssertPath "$EXEDIR\profile\programme-cache" "absent"
  !insertmacro AssertPath "$EXEDIR\profile\videos\episode.mp4" "present"
  !insertmacro AssertPath "$EXEDIR\profile\videos\unfinished.part" "present"
  !insertmacro AssertPath "$EXEDIR\external-videos\episode.mp4" "present"
  !insertmacro AssertPath "$EXEDIR\linked-data\keep.json" "present"
  !insertmacro AssertPath "$EXEDIR\profile\linked" "present"

  ; A download destination can also be the private root itself.
  !insertmacro WriteFixture "$EXEDIR\profile\.sctv-dl.lock"
  !insertmacro WriteFixture "$EXEDIR\profile\episode.mp4"
  Push "$EXEDIR\profile"
  Call SctvClearPrivateData
  !insertmacro AssertPath "$EXEDIR\profile\episode.mp4" "present"
  FileWrite $9 "PASS: normal uninstall, upgrade, unrelated values, stale installation, and download preservation$\r$\n"
  done:
  FileClose $9
  DeleteRegKey HKCU "${MANUKEY}"
  DeleteRegKey /ifempty HKCU "Software\SctvInstallerTests"
SectionEnd
