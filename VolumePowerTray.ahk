#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
;  Volume & Power Tray
;  ----------------------------------------------------------
;  Resta nel tray di Windows e gestisce hotkey globali per:
;    - Volume su / giu'
;    - Sospensione (sleep)
;    - Spegnimento (con conferma)
;
;  La configurazione sta nel file VolumePowerTray.ini, accanto
;  all'eseguibile. Si modifica dalla finestra "Impostazioni"
;  del menu del tray (oppure a mano nel file .ini): non serve
;  ricompilare.
; ============================================================

APP_VERSION := "1.2"
ConfigFile := A_ScriptDir "\VolumePowerTray.ini"
CONFIG_SECTION := "Impostazioni"

; valori predefiniti (usati se il file .ini manca o una voce e' assente)
Defaults := Map(
    "VolumeUp",        "F11",
    "VolumeDown",      "F10",
    "Sleep",           "F1",
    "Shutdown",        "F2",
    "UsaTastiMedia",   "1",
    "SecondiConferma", "5",
    "TieniSveglio",    "Off",
    "TieniSchermo",    "0",
    "SospensioneAuto", "0",
    "SospensioneOra",  "01:00")

Cfg := Map()          ; configurazione corrente (chiave -> valore)
Registered := Map()   ; hotkey attualmente registrati (azione -> stringa tasto)
g_FirstRun := false   ; true se il file .ini e' stato appena creato (prima esecuzione)
g_CdActive := false   ; true mentre una finestra di conto alla rovescia e' gia' aperta
g_AwakeMode := "Off"   ; modalita' "Tieni sveglio": "Off" | "Indefinitamente" | una durata (es. "1 ora")
g_KeepScreen := false  ; true = tieni acceso anche lo schermo
g_AwakeExpiry := 0     ; A_TickCount di scadenza dell'intervallo (0 = nessuna scadenza)
g_SleepTarget := ""     ; prossima sospensione automatica (YYYYMMDDHH24MISS), "" = disattivato
AUTO_SLEEP_SECS := 60   ; conto alla rovescia prima della sospensione automatica
INTERVAL_MIN := Map("30 minuti", 30, "1 ora", 60, "2 ore", 120, "4 ore", 240, "8 ore", 480, "12 ore", 720)  ; durate per "Per un intervallo"

LoadConfig()
RegisterHotkeys()


; ---------- Icona del tray ----------
if A_IsCompiled {
    try TraySetIcon(A_ScriptFullPath)                   ; exe: usa l'icona incorporata nell'eseguibile
} else {
    try TraySetIcon(A_ScriptDir "\VolumePowerTray.ico")  ; .ahk: usa il file .ico accanto allo script
}
A_IconTip := "Volume & Power Tray"

; prova a rendere scuri i menu su Windows 11 (API uxtheme non documentate; ignorata se non supportata)
try {
    DllCall("uxtheme\#135", "Int", 2)   ; SetPreferredAppMode(2 = ForceDark)
    DllCall("uxtheme\#136")             ; FlushMenuThemes
}


; ---------- Sottomenu "Tieni sveglio" ----------
intervalMenu := Menu()
intervalMenu.Add("30 minuti", IntervalHandler)
intervalMenu.Add("1 ora",     IntervalHandler)
intervalMenu.Add("2 ore",     IntervalHandler)
intervalMenu.Add("4 ore",     IntervalHandler)
intervalMenu.Add("8 ore",     IntervalHandler)
intervalMenu.Add("12 ore",    IntervalHandler)

awakeMenu := Menu()
awakeMenu.Add("Per un intervallo", intervalMenu)                       ; sottomenu con le durate
awakeMenu.Add("Indefinitamente", (*) => AwakeSetMode("Indefinitamente"))
awakeMenu.Add("Off", (*) => AwakeSetMode("Off"))
awakeMenu.Add()                                                        ; separatore
awakeMenu.Add("Tieni acceso lo schermo", (*) => ToggleKeepScreen())    ; interruttore indipendente
awakeMenu.Check("Off")

; ---------- Sottomenu "Sospensione automatica" ----------
; la prima voce mostra l'orario ("Ogni giorno alle 01:00") e viene rinominata quando cambia
g_SleepItem := "Ogni giorno alle " Cfg["SospensioneOra"]
sleepMenu := Menu()
sleepMenu.Add(g_SleepItem, (*) => AutoSleepSet(true))
sleepMenu.Add("Off", (*) => AutoSleepSet(false))
sleepMenu.Add()                                                         ; separatore
sleepMenu.Add("Cambia orario...", (*) => ShowAutoSleepTime())


; ---------- Menu del tray (clic destro sull'icona) ----------
tray := A_TrayMenu
tray.Delete()                              ; rimuove le voci standard di AutoHotkey
tray.Add("Volume su",   (*) => VolumeUp())
tray.Add("Volume giu'", (*) => VolumeDown())
tray.Add("Sospendi",    (*) => DoSleep())
tray.Add("Spegni...",   (*) => DoShutdown())
tray.Add()                                 ; separatore
tray.Add("Tieni sveglio", awakeMenu)       ; sottomenu nativo
tray.Add("Sospensione automatica", sleepMenu)
tray.Add()                                 ; separatore
tray.Add("Impostazioni...",   (*) => ShowSettings())
tray.Add("Avvia con Windows", (*) => ToggleStartup())
tray.Add("Mostra hotkey",     (*) => ShowInfo())
tray.Add("Info",              (*) => ShowAbout())
tray.Add()                                 ; separatore
tray.Add("Esci", (*) => ExitApp())
tray.Default := "Mostra hotkey"
UpdateStartupCheck()

; ---------- Icone delle voci del menu (incorporate nell'exe, estratte in %TEMP%) ----------
iconDir := A_Temp "\VolumePowerTray_icons"
try DirCreate(iconDir)
FileInstall("icons\volsu.ico",        iconDir "\volsu.ico", 1)
FileInstall("icons\volgiu.ico",       iconDir "\volgiu.ico", 1)
FileInstall("icons\sospendi.ico",     iconDir "\sospendi.ico", 1)
FileInstall("icons\spegni.ico",       iconDir "\spegni.ico", 1)
FileInstall("icons\sveglio.ico",      iconDir "\sveglio.ico", 1)
FileInstall("icons\impostazioni.ico", iconDir "\impostazioni.ico", 1)
FileInstall("icons\hotkey.ico",       iconDir "\hotkey.ico", 1)
FileInstall("icons\info.ico",         iconDir "\info.ico", 1)
FileInstall("icons\esci.ico",         iconDir "\esci.ico", 1)
for voce, nomeFile in Map(
    "Volume su", "volsu",  "Volume giu'", "volgiu",  "Sospendi", "sospendi",
    "Spegni...", "spegni",  "Tieni sveglio", "sveglio",  "Sospensione automatica", "sospendi",
    "Impostazioni...", "impostazioni",
    "Mostra hotkey", "hotkey",  "Info", "info",  "Esci", "esci")
    try tray.SetIcon(voce, iconDir "\" nomeFile ".ico")

; ripristina lo stato "Tieni sveglio" salvato (gli intervalli non vengono ripristinati)
g_AwakeMode  := (Cfg["TieniSveglio"] = "Indefinitamente") ? "Indefinitamente" : "Off"
g_KeepScreen := (Cfg["TieniSchermo"] = "1")
ApplyAwake()
ApplyAutoSleep()
OnMessage(0x218, OnPowerBroadcast)         ; WM_POWERBROADCAST: riapplica al risveglio


; ---------- Onboarding / notifica all'avvio ----------
if g_FirstRun
    ShowInfo()                             ; prima esecuzione: mostra subito gli hotkey


; ============================================================
;  CONFIGURAZIONE (lettura/scrittura del file .ini)
; ============================================================
LoadConfig() {
    global Cfg, Defaults, ConfigFile, CONFIG_SECTION, g_FirstRun
    if !FileExist(ConfigFile) {
        CreateDefaultConfig()
        g_FirstRun := true
    }
    ; versioni precedenti: lo "Spegnimento automatico" e' diventato "Sospensione automatica"
    for vecchia, nuova in Map("SpegnimentoAuto", "SospensioneAuto", "SpegnimentoOra", "SospensioneOra") {
        v := IniRead(ConfigFile, CONFIG_SECTION, vecchia, "")
        if (v != "") {
            if (IniRead(ConfigFile, CONFIG_SECTION, nuova, "") = "")
                try IniWrite(v, ConfigFile, CONFIG_SECTION, nuova)
            try IniDelete(ConfigFile, CONFIG_SECTION, vecchia)
        }
    }
    Cfg := Map()
    for chiave, predef in Defaults
        Cfg[chiave] := IniRead(ConfigFile, CONFIG_SECTION, chiave, predef)
    if !RegExMatch(Cfg["SospensioneOra"], "^([01]\d|2[0-3]):[0-5]\d$")
        Cfg["SospensioneOra"] := Defaults["SospensioneOra"]
}

CreateDefaultConfig() {
    global ConfigFile, CONFIG_SECTION, Defaults
    testo := "; ============================================================`r`n"
        . "; Volume & Power Tray - configurazione`r`n"
        . "; ============================================================`r`n"
        . "; Modifica i valori qui sotto oppure usa la finestra Impostazioni`r`n"
        . "; nel menu del tray (clic destro sull'icona).`r`n"
        . ";`r`n"
        . "; Tasti (modificatori):  ^ = Ctrl   ! = Alt   + = Shift   # = Win`r`n"
        . ";   esempi:  F11   ^!Up   #PgUp   ^!s`r`n"
        . ";`r`n"
        . "; UsaTastiMedia    1 = mostra la barra volume di Windows, 0 = cambio silenzioso`r`n"
        . "; SecondiConferma  durata del conto alla rovescia prima di sleep/spegnimento`r`n"
        . "; TieniSveglio     Off | Indefinitamente   (gli intervalli non vengono ricordati)`r`n"
        . "; TieniSchermo     1 = tieni acceso anche lo schermo quando sei sveglio`r`n"
        . "; SospensioneAuto  1 = sospendi il PC ogni giorno all'orario SospensioneOra`r`n"
        . "; SospensioneOra   orario della sospensione automatica (HH:MM, es. 01:00)`r`n"
        . "; ============================================================`r`n"
        . "`r`n"
        . "[" CONFIG_SECTION "]`r`n"
        . "VolumeUp=" Defaults["VolumeUp"] "`r`n"
        . "VolumeDown=" Defaults["VolumeDown"] "`r`n"
        . "Sleep=" Defaults["Sleep"] "`r`n"
        . "Shutdown=" Defaults["Shutdown"] "`r`n"
        . "UsaTastiMedia=" Defaults["UsaTastiMedia"] "`r`n"
        . "SecondiConferma=" Defaults["SecondiConferma"] "`r`n"
        . "TieniSveglio=" Defaults["TieniSveglio"] "`r`n"
        . "TieniSchermo=" Defaults["TieniSchermo"] "`r`n"
        . "SospensioneAuto=" Defaults["SospensioneAuto"] "`r`n"
        . "SospensioneOra=" Defaults["SospensioneOra"] "`r`n"
    try FileAppend(testo, ConfigFile)
}

SaveConfig() {
    global Cfg, ConfigFile, CONFIG_SECTION
    for chiave, valore in Cfg
        try IniWrite(valore, ConfigFile, CONFIG_SECTION, chiave)
}

ConfirmSecs() {
    global Cfg
    v := Cfg["SecondiConferma"]
    return (IsInteger(v) && v + 0 >= 1) ? v + 0 : 5
}

; ============================================================
;  REGISTRAZIONE DEGLI HOTKEY GLOBALI
; ============================================================
; Disattiva i tasti precedenti e attiva quelli della config corrente.
; Puo' essere richiamata dopo un salvataggio per applicare le modifiche.
RegisterHotkeys() {
    global Cfg, Registered
    azioni := Map("VolumeUp", VolumeUp, "VolumeDown", VolumeDown, "Sleep", DoSleep, "Shutdown", DoShutdown)
    errori := ""
    for azione, fn in azioni {
        nuovo := Cfg[azione]
        if (Registered.Has(azione) && Registered[azione] != "" && Registered[azione] != nuovo)
            try Hotkey(Registered[azione], fn, "Off")     ; spegne il vecchio tasto
        try {
            Hotkey(nuovo, fn, "On")                        ; attiva il nuovo
            Registered[azione] := nuovo
        } catch {
            errori .= "- " azione ": '" nuovo "' non e' un tasto valido`n"
            Registered[azione] := ""
        }
    }
    if (errori != "")
        MsgBox("Questi tasti non sono validi e non sono stati attivati:`n`n" errori
            . "`nControlla la finestra Impostazioni.", "Volume & Power Tray", "Icon!")
}


; ============================================================
;  AZIONI
; ============================================================
VolumeUp(*) {
    global Cfg
    if (Cfg["UsaTastiMedia"] = "1")
        Send "{Volume_Up}"                 ; tasto multimediale: mostra la barra volume
    else
        SoundSetVolume "+5"                ; cambio silenzioso del 5%
}

VolumeDown(*) {
    global Cfg
    if (Cfg["UsaTastiMedia"] = "1")
        Send "{Volume_Down}"
    else
        SoundSetVolume "-5"
}

DoSleep(*) {
    CountdownConfirm("Sospensione", "Annulla sleep", ConfirmSecs(), SuspendNow)
}
SuspendNow() {
    ; SetSuspendState: primo argomento 0 = sospendi (sleep), 1 = iberna
    DllCall("PowrProf\SetSuspendState", "Int", 0, "Int", 0, "Int", 0)
}

DoShutdown(*) {
    CountdownConfirm("Spegnimento", "Annulla spegnimento", ConfirmSecs(), ShutdownNow)
}
; Il comando Shutdown di AHK (ExitWindowsEx) con altri utenti collegati (cambio rapido
; utente) apre un dialogo di user32 "Other people are logged on..." che blocca tutto
; finche' qualcuno non risponde: per questo NON va usato. InitiateShutdownW con
; SHUTDOWN_FORCE_OTHERS disconnette le altre sessioni e spegne senza chiedere; se
; fallisce si ripiega su shutdown.exe. Gli esiti finiscono in VolumePowerTray.log.
ShutdownNow() {
    priv := EnableShutdownPrivilege()
    ; 0x1 SHUTDOWN_FORCE_OTHERS | 0x2 SHUTDOWN_FORCE_SELF | 0x8 SHUTDOWN_POWEROFF; motivo 0 = Altro
    err := DllCall("Advapi32\InitiateShutdownW", "Ptr", 0, "Ptr", 0, "UInt", 0
        , "UInt", 0x1 | 0x2 | 0x8, "UInt", 0, "UInt")
    WriteLog("Spegnimento: privilegio=" priv ", InitiateShutdownW=" err)
    if (err = 0)
        return
    try {
        rc := RunWait(A_WinDir "\System32\shutdown.exe /s /f /t 0", , "Hide")
        WriteLog("Spegnimento: shutdown.exe exit=" rc)
    } catch as e {
        WriteLog("Spegnimento: shutdown.exe non avviato (" e.Message ")")
    }
}

; InitiateShutdownW richiede che il privilegio SeShutdownPrivilege sia attivo nel token.
; Restituisce "ok" oppure una descrizione dell'errore (per il log).
EnableShutdownPrivilege() {
    if !DllCall("Advapi32\OpenProcessToken", "Ptr", DllCall("GetCurrentProcess", "Ptr")
            , "UInt", 0x28, "Ptr*", &hToken := 0)       ; TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY
        return "OpenProcessToken " A_LastError
    tp := Buffer(16, 0)                                 ; TOKEN_PRIVILEGES con un solo LUID_AND_ATTRIBUTES
    NumPut("UInt", 1, tp, 0)
    esito := "ok"
    if DllCall("Advapi32\LookupPrivilegeValueW", "Ptr", 0, "Str", "SeShutdownPrivilege", "Ptr", tp.Ptr + 4) {
        NumPut("UInt", 2, tp, 12)                       ; SE_PRIVILEGE_ENABLED
        DllCall("Advapi32\AdjustTokenPrivileges", "Ptr", hToken, "Int", 0, "Ptr", tp, "UInt", 0, "Ptr", 0, "Ptr", 0)
        if (A_LastError != 0)                           ; 1300 = ERROR_NOT_ALL_ASSIGNED
            esito := "AdjustTokenPrivileges " A_LastError
    } else
        esito := "LookupPrivilegeValue " A_LastError
    DllCall("CloseHandle", "Ptr", hToken)
    return esito
}

WriteLog(msg) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " msg "`r`n", A_ScriptDir "\VolumePowerTray.log", "UTF-8")
}


; ============================================================
;  TIENI SVEGLIO (come PowerToys Awake)
;  Usa SetThreadExecutionState per impedire la sospensione e,
;  a scelta, lo spegnimento dello schermo. La modalita' ("Off",
;  "Indefinitamente" o una durata) e' separata dall'interruttore
;  "Tieni acceso lo schermo".
; ============================================================
AwakeSetMode(modo, minuti := 0) {
    global g_AwakeMode, g_AwakeExpiry
    SetTimer(AwakeExpire, 0)                ; annulla un eventuale timer di scadenza
    g_AwakeMode := modo
    g_AwakeExpiry := (minuti > 0) ? (A_TickCount + minuti * 60000) : 0
    if (minuti > 0)
        SetTimer(AwakeExpire, -minuti * 60000)   ; one-shot: torna a Off allo scadere
    ApplyAwake()
    SaveAwake()
}

AwakeExpire() {
    AwakeSetMode("Off")
}

; Salva nello .ini lo stato "Tieni sveglio". Gli intervalli vengono salvati come Off
; (un tempo residuo non avrebbe senso dopo un riavvio).
SaveAwake() {
    global Cfg, g_AwakeMode, g_KeepScreen, ConfigFile, CONFIG_SECTION
    Cfg["TieniSveglio"] := (g_AwakeMode = "Indefinitamente") ? "Indefinitamente" : "Off"
    Cfg["TieniSchermo"] := g_KeepScreen ? "1" : "0"
    try IniWrite(Cfg["TieniSveglio"], ConfigFile, CONFIG_SECTION, "TieniSveglio")
    try IniWrite(Cfg["TieniSchermo"], ConfigFile, CONFIG_SECTION, "TieniSchermo")
}

; Applica lo stato corrente al sistema e aggiorna menu/tooltip.
ApplyAwake() {
    global g_AwakeMode, g_KeepScreen
    flags := 0x80000000                     ; ES_CONTINUOUS
    if (g_AwakeMode != "Off") {
        flags |= 0x00000001                 ; ES_SYSTEM_REQUIRED  -> niente sospensione
        if g_KeepScreen
            flags |= 0x00000002             ; ES_DISPLAY_REQUIRED -> schermo sempre acceso
    }
    DllCall("kernel32\SetThreadExecutionState", "UInt", flags)
    ; ri-asserzione periodica: ogni 50s ripete la richiesta continua, perche'
    ; Windows puo' scartarla dopo un ciclo di sospensione/ripresa
    SetTimer(AwakeKeepAlive, (g_AwakeMode != "Off") ? 50000 : 0)
    UpdateAwakeMenu()
    UpdateAwakeTip()
}

; Ripetuta ogni 50s mentre "Tieni sveglio" e' attivo: ristabilisce la richiesta
; continua. Senza ES_CONTINUOUS il "poke" momentaneo non basta a impedire lo
; sleep su Windows 10/11, e la richiesta continua puo' andare persa dopo una
; sospensione/ripresa: ripeterla identica ogni 50s copre entrambi i casi.
AwakeKeepAlive() {
    global g_AwakeMode, g_KeepScreen
    if (g_AwakeMode = "Off") {
        SetTimer(AwakeKeepAlive, 0)
        return
    }
    flags := 0x80000000 | 0x00000001        ; ES_CONTINUOUS | ES_SYSTEM_REQUIRED
    if g_KeepScreen
        flags |= 0x00000002                 ; ES_DISPLAY_REQUIRED
    DllCall("kernel32\SetThreadExecutionState", "UInt", flags)
    UpdateAwakeTip()                        ; aggiorna il tempo rimanente nel tooltip
}

; Chiamata da Windows ai cambi di stato di alimentazione (WM_POWERBROADCAST):
; al risveglio dalla sospensione ristabilisce subito la richiesta "Tieni sveglio",
; senza aspettare fino a 50s la ri-asserzione periodica.
OnPowerBroadcast(wParam, lParam, msg, hwnd) {
    global g_AwakeMode
    if (wParam = 0x12) {                    ; PBT_APMRESUMEAUTOMATIC: sistema appena ripreso
        if (g_AwakeMode != "Off")
            ApplyAwake()
        AutoSleepCheck()                     ; se l'orario e' passato durante la sospensione, lo salta
        return true
    }
}

IntervalHandler(itemName, *) {
    global INTERVAL_MIN
    AwakeSetMode(itemName, INTERVAL_MIN[itemName])
}

ToggleKeepScreen() {
    global g_KeepScreen
    g_KeepScreen := !g_KeepScreen
    ApplyAwake()
    SaveAwake()
}

; Aggiorna le spunte del sottomenu "Tieni sveglio" in base allo stato corrente.
UpdateAwakeMenu() {
    global awakeMenu, intervalMenu, g_AwakeMode, g_KeepScreen, INTERVAL_MIN
    awakeMenu.Uncheck("Indefinitamente")
    awakeMenu.Uncheck("Off")
    awakeMenu.Uncheck("Per un intervallo")
    for etichetta, m in INTERVAL_MIN
        intervalMenu.Uncheck(etichetta)
    if (g_AwakeMode = "Indefinitamente")
        awakeMenu.Check("Indefinitamente")
    else if (g_AwakeMode = "Off")
        awakeMenu.Check("Off")
    else {                                   ; una durata: spunta sia il sottomenu sia la voce
        awakeMenu.Check("Per un intervallo")
        intervalMenu.Check(g_AwakeMode)
    }
    if g_KeepScreen
        awakeMenu.Check("Tieni acceso lo schermo")
    else
        awakeMenu.Uncheck("Tieni acceso lo schermo")
}

UpdateAwakeTip() {
    global g_AwakeMode, g_KeepScreen, g_SleepTarget, Cfg
    tip := "Volume & Power Tray"
    if (g_AwakeMode != "Off") {
        extra := g_KeepScreen ? " (+ schermo)" : ""
        rim := RemainingText()
        tip .= "`nSveglio: " g_AwakeMode extra (rim != "" ? " - resta " rim : "")
    }
    if (g_SleepTarget != "")
        tip .= "`nSospensione alle " Cfg["SospensioneOra"]
    A_IconTip := tip
}

; Tempo rimanente prima della scadenza dell'intervallo (es. "1 h 23 min"); "" se non c'e' scadenza.
RemainingText() {
    global g_AwakeExpiry
    if (g_AwakeExpiry = 0)
        return ""
    ms := g_AwakeExpiry - A_TickCount
    if (ms <= 0)
        return ""
    totSec := ms // 1000
    h := totSec // 3600
    m := Mod(totSec, 3600) // 60
    s := Mod(totSec, 60)
    if (h > 0)
        return h " h " m " min"
    if (m > 0)
        return m " min " s " s"
    return s " s"
}

; Testo leggibile dello stato "Tieni sveglio" (usato anche nella finestra Mostra hotkey).
AwakeStateText() {
    global g_AwakeMode, g_KeepScreen
    if (g_AwakeMode = "Off")
        return "Off"
    rim := RemainingText()
    return g_AwakeMode (g_KeepScreen ? " + schermo" : "") (rim != "" ? "  (resta " rim ")" : "")
}


; ============================================================
;  SOSPENSIONE AUTOMATICA
;  Ogni giorno all'orario SospensioneOra mostra il conto alla
;  rovescia (annullabile) e poi sospende. Se a quell'ora il PC era
;  gia' sospeso, la sospensione di quel giorno viene saltata.
; ============================================================
AutoSleepSet(attivo) {
    global Cfg, ConfigFile, CONFIG_SECTION
    Cfg["SospensioneAuto"] := attivo ? "1" : "0"
    try IniWrite(Cfg["SospensioneAuto"], ConfigFile, CONFIG_SECTION, "SospensioneAuto")
    ApplyAutoSleep()
}

; Calcola la prossima sospensione e avvia/ferma il controllo periodico.
ApplyAutoSleep() {
    global Cfg, g_SleepTarget
    if (Cfg["SospensioneAuto"] = "1") {
        g_SleepTarget := NextSleepTarget()
        SetTimer(AutoSleepCheck, 20000)
    } else {
        g_SleepTarget := ""
        SetTimer(AutoSleepCheck, 0)
    }
    UpdateAutoSleepMenu()
    UpdateAwakeTip()
}

; Prossima occorrenza futura di SospensioneOra (oggi o domani), come YYYYMMDDHH24MISS.
NextSleepTarget() {
    global Cfg
    t := FormatTime(A_Now, "yyyyMMdd") StrReplace(Cfg["SospensioneOra"], ":") "00"
    return (t > A_Now) ? t : DateAdd(t, 1, "Days")
}

; Ogni 20s (e alla ripresa dalla sospensione): se l'orario e' arrivato sospende,
; con conto alla rovescia. Un ritardo oltre 2 minuti significa che il PC era
; sospeso a quell'ora: in quel caso non fa nulla. In entrambi i casi passa al giorno dopo.
AutoSleepCheck() {
    global g_SleepTarget, AUTO_SLEEP_SECS
    if (g_SleepTarget = "" || A_Now < g_SleepTarget)
        return
    ritardo := DateDiff(A_Now, g_SleepTarget, "Seconds")
    g_SleepTarget := NextSleepTarget()
    if (ritardo <= 120)
        CountdownConfirm("Sospensione", "Annulla sleep", AUTO_SLEEP_SECS, SuspendNow)
}

UpdateAutoSleepMenu() {
    global sleepMenu, g_SleepItem, g_SleepTarget
    if (g_SleepTarget != "") {
        sleepMenu.Check(g_SleepItem)
        sleepMenu.Uncheck("Off")
    } else {
        sleepMenu.Uncheck(g_SleepItem)
        sleepMenu.Check("Off")
    }
}

; Testo leggibile dello stato della sospensione automatica (per la finestra Mostra hotkey).
AutoSleepStateText() {
    global Cfg, g_SleepTarget
    if (g_SleepTarget = "")
        return "Off"
    min := DateDiff(g_SleepTarget, A_Now, "Minutes")
    return "Alle " Cfg["SospensioneOra"] "  (tra " (min >= 60 ? min // 60 " h " Mod(min, 60) " min" : min " min") ")"
}

; Finestrella per scegliere l'orario; salvando attiva anche la sospensione automatica.
ShowAutoSleepTime() {
    global Cfg
    g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Sospensione automatica")
    g.BackColor := "White"
    g.MarginX := 20
    g.MarginY := 16
    g.SetFont("s10", "Segoe UI")
    g.AddText("x20 y19 w160", "Sospendi ogni giorno alle")
    dt := g.AddDateTime("x182 y16 w80 1", "HH:mm")                  ; 1 = frecce su/giu' al posto del calendario
    dt.Value := "20000101" StrReplace(Cfg["SospensioneOra"], ":") "00"
    g.SetFont("s9", "Segoe UI")
    g.AddText("x20 y50 w235 c808080", "Se a quell'ora il PC e' gia' sospeso, non fa nulla.")
    btnOk := g.AddButton("x75 y80 w88 Default", "Salva")
    btnAnn := g.AddButton("x167 y80 w88", "Annulla")

    Salva(*) {
        global Cfg, ConfigFile, CONFIG_SECTION, sleepMenu, g_SleepItem
        v := dt.Value
        Cfg["SospensioneOra"] := SubStr(v, 9, 2) ":" SubStr(v, 11, 2)
        try IniWrite(Cfg["SospensioneOra"], ConfigFile, CONFIG_SECTION, "SospensioneOra")
        nuovo := "Ogni giorno alle " Cfg["SospensioneOra"]
        if (nuovo != g_SleepItem) {
            sleepMenu.Rename(g_SleepItem, nuovo)
            g_SleepItem := nuovo
        }
        g.Destroy()
        AutoSleepSet(true)
    }
    Annulla(*) => g.Destroy()
    btnOk.OnEvent("Click", Salva)
    btnAnn.OnEvent("Click", Annulla)
    g.OnEvent("Close", Annulla)
    g.OnEvent("Escape", Annulla)
    g.Show("Center")
}


; ============================================================
;  FINESTRA CON CONTO ALLA ROVESCIA
;  Mostra "<verbo> tra N secondi..." con un solo pulsante per
;  annullare. Allo scadere, se non e' stato annullato, esegue Action.
;  Invio o Esc = annulla.
; ============================================================
CountdownConfirm(verbo, etichettaAnnulla, secondi, Action) {
    global g_CdActive
    if g_CdActive                          ; evita finestre sovrapposte se si ripreme il tasto
        return
    g_CdActive := true
    rimanenti := secondi

    g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Volume & Power Tray")
    g.MarginX := 18
    g.MarginY := 16
    g.SetFont("s11", "Segoe UI")
    try {                                  ; icona di avviso di sistema (triangolo giallo)
        hIcon := DllCall("LoadIconW", "Ptr", 0, "Ptr", 32515, "Ptr")   ; IDI_WARNING
        g.AddPicture("x18 y16 w32 h32", "HICON:" hIcon)
    }
    txt := g.AddText("x60 y20 w270 h34 0x200")   ; testo a destra dell'icona, centrato in verticale
    g.AddButton("x84 y70 w180 Default", etichettaAnnulla).OnEvent("Click", Annulla)
    g.OnEvent("Close", Annulla)            ; chiusura con la X
    g.OnEvent("Escape", Annulla)           ; tasto Esc
    Aggiorna()
    g.Show("Center")
    SetTimer(Tick, 1000)

    Aggiorna() => txt.Text := verbo " tra " rimanenti " second" (rimanenti = 1 ? "o" : "i") "..."

    Tick() {
        global g_CdActive
        rimanenti--
        if (rimanenti > 0) {
            Aggiorna()
            return
        }
        SetTimer(Tick, 0)                  ; tempo scaduto: ferma il timer ed esegui
        g_CdActive := false
        g.Destroy()
        Action()
    }

    Annulla(*) {
        global g_CdActive
        SetTimer(Tick, 0)                  ; annullato: ferma il timer e chiudi
        g_CdActive := false
        g.Destroy()
    }
}


; ============================================================
;  FINESTRA IMPOSTAZIONI
; ============================================================
ShowSettings(*) {
    global Cfg, Defaults

    s := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Impostazioni - Volume & Power Tray")
    s.BackColor := "White"
    s.MarginX := 20
    s.MarginY := 16

    s.SetFont("s12 Bold", "Segoe UI")
    s.AddText("x20 y16 w400 c2563EB", "Impostazioni")
    s.AddText("x20 y46 w400 0x10", "")

    ; --- Tasti (con pulsante "Premi" per assegnare al volo) ---
    s.SetFont("s10 Bold", "Segoe UI")
    s.AddText("x20 y58", "Tasti")
    s.SetFont("s10", "Segoe UI")
    campi := Map()
    etichette := [["VolumeUp",   "Volume su"]
                , ["VolumeDown", "Volume giu'"]
                , ["Sleep",      "Sospendi (sleep)"]
                , ["Shutdown",   "Spegni"]]
    y := 84
    for i, e in etichette {
        s.AddText("x28 y" (y + 3) " w140", e[2])
        ed := s.AddEdit("x172 y" y " w160", Cfg[e[1]])
        campi[e[1]] := ed
        s.AddButton("x340 y" (y - 1) " w70", "Premi").OnEvent("Click", CapturaPer(ed, s.Hwnd))
        y += 30
    }

    s.SetFont("s9", "Segoe UI")
    s.AddText("x28 y" (y + 2) " w382 c808080",
        "Scrivi il tasto o usa 'Premi'.   Modificatori:  ^ Ctrl   ! Alt   + Shift   # Win")
    y += 30

    ; --- Opzioni ---
    s.SetFont("s10 Bold", "Segoe UI")
    s.AddText("x20 y" y, "Opzioni")
    s.SetFont("s10", "Segoe UI")
    y += 28
    chkMedia := s.AddCheckBox("x28 y" y " w382 " (Cfg["UsaTastiMedia"] = "1" ? "Checked" : ""),
        "Mostra la barra del volume di Windows")
    y += 32
    s.AddText("x28 y" (y + 3) " w150", "Secondi conferma")
    editSec := s.AddEdit("x180 y" y " w80 Number", Cfg["SecondiConferma"])
    y += 42

    s.AddText("x20 y" y " w400 0x10", "")
    y += 12

    btnDefault := s.AddButton("x20 y" y " w150", "Ripristina default")
    btnSalva   := s.AddButton("x225 y" y " w95 Default", "Salva")
    btnAnnulla := s.AddButton("x325 y" y " w95", "Annulla")

    Salva(*) {
        global Cfg
        Cfg["VolumeUp"]        := Trim(campi["VolumeUp"].Value)
        Cfg["VolumeDown"]      := Trim(campi["VolumeDown"].Value)
        Cfg["Sleep"]           := Trim(campi["Sleep"].Value)
        Cfg["Shutdown"]        := Trim(campi["Shutdown"].Value)
        Cfg["UsaTastiMedia"]   := chkMedia.Value ? "1" : "0"
        Cfg["SecondiConferma"] := ValidaNumero(editSec.Value, 5)
        SaveConfig()
        RegisterHotkeys()
        s.Destroy()
    }
    Annulla(*) => s.Destroy()
    Ripristina(*) {
        global Defaults
        for k, c in campi
            c.Value := Defaults[k]
        chkMedia.Value  := (Defaults["UsaTastiMedia"] = "1")
        editSec.Value   := Defaults["SecondiConferma"]
    }
    btnSalva.OnEvent("Click", Salva)
    btnAnnulla.OnEvent("Click", Annulla)
    btnDefault.OnEvent("Click", Ripristina)
    s.OnEvent("Close", Annulla)
    s.OnEvent("Escape", Annulla)
    s.Show("Center")
}

ValidaNumero(v, predef) {
    return (IsInteger(v) && v + 0 >= 1) ? String(v + 0) : String(predef)
}

; Restituisce un gestore di click che cattura un tasto nel campo dato.
CapturaPer(edit, ownerHwnd) => (*) => AssegnaTasto(edit, ownerHwnd)

; Mostra un piccolo prompt e registra la prossima combinazione premuta nel campo.
AssegnaTasto(edit, ownerHwnd) {
    p := Gui("+AlwaysOnTop -Caption +Owner" ownerHwnd)
    p.BackColor := "2563EB"
    p.MarginX := 20
    p.MarginY := 16
    p.SetFont("s11 Bold cFFFFFF", "Segoe UI")
    p.AddText("w240 Center", "Premi la combinazione di tasti")
    p.SetFont("s9 Norm cDDE3FF", "Segoe UI")
    p.AddText("w240 Center", "(Esc per annullare)")
    p.Show("Center")

    prev := A_IsSuspended
    Suspend(true)                          ; evita che il tasto premuto scateni la sua azione
    ih := InputHook("")
    ih.KeyOpt("{All}", "ES")               ; ogni tasto termina (E) e viene soppresso (S)
    ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-E")  ; i modificatori non terminano
    ih.Start()
    ih.Wait(10)                            ; max 10 secondi
    Suspend(prev)
    p.Destroy()

    if (ih.EndReason != "EndKey" || ih.EndKey = "Escape")
        return
    mods := ""
    for i, sym in ["^", "!", "+", "#"]
        if InStr(ih.EndMods, sym)
            mods .= sym
    edit.Value := mods ih.EndKey
}


; ============================================================
;  FINESTRA "MOSTRA HOTKEY"
; ============================================================
ShowInfo(*) {
    global Cfg
    accent := "c2563EB"   ; blu di accento, come l'icona

    g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Volume & Power Tray")
    g.BackColor := "White"
    g.SetFont("s10", "Segoe UI")
    g.MarginX := 22
    g.MarginY := 18

    iconSrc := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\VolumePowerTray.ico"
    try g.AddPicture("x22 y18 w28 h28 Icon1", iconSrc)
    g.SetFont("s13 Bold", "Segoe UI")
    g.AddText("x60 y23 w288 " accent, "Hotkey attivi")

    g.AddText("x22 y56 w326 0x10", "")

    righe := [["Volume su",   Cfg["VolumeUp"]]
            , ["Volume giu'", Cfg["VolumeDown"]]
            , ["Sospendi",    Cfg["Sleep"]]
            , ["Spegni",      Cfg["Shutdown"]]]
    for i, r in righe {
        y := 70 + (i - 1) * 30
        g.SetFont("s10", "Segoe UI")
        g.AddText("x22 y" (y + 3) " w150 c444444", r[1])
        g.SetFont("s10 Bold", "Segoe UI")
        g.AddText("x180 y" y " w168 h24 Center 0x200 Border BackgroundF5F5F5 c222222", PrettyKeys(r[2]))
    }
    yEnd := 70 + righe.Length * 30

    ; separatore
    g.AddText("x22 y" (yEnd + 4) " w326 0x10", "")

    ; stato "Tieni sveglio"
    g.SetFont("s10", "Segoe UI")
    g.AddText("x22 y" (yEnd + 16) " w110 c444444", "Tieni sveglio")
    g.SetFont("s10 Bold", "Segoe UI")
    g.AddText("x140 y" (yEnd + 16) " w208 c2563EB", AwakeStateText())

    ; stato "Sospensione automatica"
    g.SetFont("s10", "Segoe UI")
    g.AddText("x22 y" (yEnd + 44) " w110 c444444", "Sospensione")
    g.SetFont("s10 Bold", "Segoe UI")
    g.AddText("x140 y" (yEnd + 44) " w208 c2563EB", AutoSleepStateText())

    ; separatore + nota
    g.AddText("x22 y" (yEnd + 72) " w326 0x10", "")
    g.SetFont("s9", "Segoe UI")
    g.AddText("x22 y" (yEnd + 84) " w326 c808080",
        "Per cambiare i tasti usa 'Impostazioni...' nel menu del tray.")

    g.SetFont("s9", "Segoe UI")
    btn := g.AddButton("x258 y" (yEnd + 132) " w90 Default", "OK")
    Chiudi(*) => g.Destroy()
    btn.OnEvent("Click", Chiudi)
    g.OnEvent("Close", Chiudi)
    g.OnEvent("Escape", Chiudi)

    g.Show("Center")
}


; ============================================================
;  FINESTRA "INFO"
; ============================================================
ShowAbout(*) {
    global APP_VERSION

    g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Info - Volume & Power Tray")
    g.BackColor := "White"
    g.MarginX := 22
    g.MarginY := 20

    iconSrc := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\VolumePowerTray.ico"
    try g.AddPicture("x22 y22 w44 h44 Icon1", iconSrc)
    g.SetFont("s13 Bold c2563EB", "Segoe UI")
    g.AddText("x78 y24", "Volume & Power Tray")
    g.SetFont("s9 c666666", "Segoe UI")
    g.AddText("x78 y50", "Versione " APP_VERSION)

    g.SetFont("s10 c333333", "Segoe UI")
    g.AddText("x22 y84 w330",
        "Piccola utility da tray per controllare volume, sospensione e spegnimento tramite hotkey personalizzabili.")

    g.SetFont("s9", "Segoe UI")
    btn := g.AddButton("x262 y140 w90 Default", "OK")
    Chiudi(*) => g.Destroy()
    btn.OnEvent("Click", Chiudi)
    g.OnEvent("Close", Chiudi)
    g.OnEvent("Escape", Chiudi)

    g.Show("Center")
}

; Converte una stringa hotkey (es. "^!Up") in testo leggibile (es. "Ctrl + Alt + Up")
PrettyKeys(hk) {
    out := ""
    for sym, name in Map("^","Ctrl", "!","Alt", "+","Shift", "#","Win") {
        if InStr(hk, sym) {
            out .= name " + "
            hk := StrReplace(hk, sym)
        }
    }
    return out . StrUpper(SubStr(hk, 1, 1)) . SubStr(hk, 2)
}


; ============================================================
;  AVVIO AUTOMATICO CON WINDOWS
;  Crea o rimuove un collegamento all'eseguibile nella cartella
;  Esecuzione automatica.
; ============================================================
StartupLink() => A_Startup "\VolumePowerTray.lnk"

ToggleStartup() {
    if FileExist(StartupLink())
        FileDelete StartupLink()
    else
        FileCreateShortcut A_ScriptFullPath, StartupLink()
    UpdateStartupCheck()
}

; Allinea la spunta della voce "Avvia con Windows" allo stato reale del collegamento.
UpdateStartupCheck() {
    A_TrayMenu.Uncheck("Avvia con Windows")
    if FileExist(StartupLink())
        A_TrayMenu.Check("Avvia con Windows")
}
