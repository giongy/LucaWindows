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

APP_VERSION := "1.1"
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
    "NotificaAvvio",   "1",
    "TieniSveglio",    "Off",
    "TieniSchermo",    "0")

Cfg := Map()          ; configurazione corrente (chiave -> valore)
Registered := Map()   ; hotkey attualmente registrati (azione -> stringa tasto)
g_FirstRun := false   ; true se il file .ini e' stato appena creato (prima esecuzione)
g_CdActive := false   ; true mentre una finestra di conto alla rovescia e' gia' aperta
g_AwakeMode := "Off"   ; modalita' "Tieni sveglio": "Off" | "Indefinitamente" | una durata (es. "1 ora")
g_KeepScreen := false  ; true = tieni acceso anche lo schermo
g_AwakeExpiry := 0     ; A_TickCount di scadenza dell'intervallo (0 = nessuna scadenza)
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


; ---------- Menu del tray (clic destro sull'icona) ----------
tray := A_TrayMenu
tray.Delete()                              ; rimuove le voci standard di AutoHotkey
tray.Add("Volume su",   (*) => VolumeUp())
tray.Add("Volume giu'", (*) => VolumeDown())
tray.Add("Sospendi",    (*) => DoSleep())
tray.Add("Spegni...",   (*) => DoShutdown())
tray.Add()                                 ; separatore
tray.Add("Tieni sveglio", awakeMenu)       ; sottomenu nativo
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
    "Spegni...", "spegni",  "Tieni sveglio", "sveglio",  "Impostazioni...", "impostazioni",
    "Mostra hotkey", "hotkey",  "Info", "info",  "Esci", "esci")
    try tray.SetIcon(voce, iconDir "\" nomeFile ".ico")

; ripristina lo stato "Tieni sveglio" salvato (gli intervalli non vengono ripristinati)
g_AwakeMode  := (Cfg["TieniSveglio"] = "Indefinitamente") ? "Indefinitamente" : "Off"
g_KeepScreen := (Cfg["TieniSchermo"] = "1")
ApplyAwake()


; ---------- Onboarding / notifica all'avvio ----------
if g_FirstRun
    ShowInfo()                             ; prima esecuzione: mostra subito gli hotkey
else if (Cfg["NotificaAvvio"] = "1")
    StartupToast()


; ============================================================
;  CONFIGURAZIONE (lettura/scrittura del file .ini)
; ============================================================
LoadConfig() {
    global Cfg, Defaults, ConfigFile, CONFIG_SECTION, g_FirstRun
    if !FileExist(ConfigFile) {
        CreateDefaultConfig()
        g_FirstRun := true
    }
    Cfg := Map()
    for chiave, predef in Defaults
        Cfg[chiave] := IniRead(ConfigFile, CONFIG_SECTION, chiave, predef)
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
        . "; NotificaAvvio    1 = mostra una notifica all'avvio, 0 = avvio silenzioso`r`n"
        . "; TieniSveglio     Off | Indefinitamente   (gli intervalli non vengono ricordati)`r`n"
        . "; TieniSchermo     1 = tieni acceso anche lo schermo quando sei sveglio`r`n"
        . "; ============================================================`r`n"
        . "`r`n"
        . "[" CONFIG_SECTION "]`r`n"
        . "VolumeUp=" Defaults["VolumeUp"] "`r`n"
        . "VolumeDown=" Defaults["VolumeDown"] "`r`n"
        . "Sleep=" Defaults["Sleep"] "`r`n"
        . "Shutdown=" Defaults["Shutdown"] "`r`n"
        . "UsaTastiMedia=" Defaults["UsaTastiMedia"] "`r`n"
        . "SecondiConferma=" Defaults["SecondiConferma"] "`r`n"
        . "NotificaAvvio=" Defaults["NotificaAvvio"] "`r`n"
        . "TieniSveglio=" Defaults["TieniSveglio"] "`r`n"
        . "TieniSchermo=" Defaults["TieniSchermo"] "`r`n"
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

StartupToast() {
    global Cfg
    msg := "Vol+ " PrettyKeys(Cfg["VolumeUp"]) "    Vol- " PrettyKeys(Cfg["VolumeDown"]) "`n"
         . "Sleep " PrettyKeys(Cfg["Sleep"]) "    Spegni " PrettyKeys(Cfg["Shutdown"])
    TrayTip(msg, "Volume & Power Tray attivo", 0x1)   ; 0x1 = icona info
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
ShutdownNow() {
    Shutdown 1     ; 1 = spegni. Se restasse appeso usa Shutdown(1+4) per forzare la chiusura delle app
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
    ; ri-asserzione periodica: ogni 50s resetta il timer di inattivita' di Windows,
    ; cosi' il sistema non si addormenta nemmeno se il flag "continuo" non bastasse
    SetTimer(AwakeKeepAlive, (g_AwakeMode != "Off") ? 50000 : 0)
    UpdateAwakeMenu()
    UpdateAwakeTip()
}

; Ripetuta ogni 50s mentre "Tieni sveglio" e' attivo: rinnova la richiesta al sistema.
AwakeKeepAlive() {
    global g_AwakeMode, g_KeepScreen
    if (g_AwakeMode = "Off") {
        SetTimer(AwakeKeepAlive, 0)
        return
    }
    flags := 0x00000001                     ; ES_SYSTEM_REQUIRED (senza CONTINUOUS = reset del timer di inattivita')
    if g_KeepScreen
        flags |= 0x00000002
    DllCall("kernel32\SetThreadExecutionState", "UInt", flags)
    UpdateAwakeTip()                        ; aggiorna il tempo rimanente nel tooltip
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
    global g_AwakeMode, g_KeepScreen
    if (g_AwakeMode = "Off") {
        A_IconTip := "Volume & Power Tray"
        return
    }
    extra := g_KeepScreen ? " (+ schermo)" : ""
    rim := RemainingText()
    A_IconTip := "Volume & Power Tray`nSveglio: " g_AwakeMode extra (rim != "" ? " - resta " rim : "")
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
    y += 28
    chkNotif := s.AddCheckBox("x28 y" y " w382 " (Cfg["NotificaAvvio"] = "1" ? "Checked" : ""),
        "Mostra una notifica all'avvio")
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
        Cfg["NotificaAvvio"]   := chkNotif.Value ? "1" : "0"
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
        chkNotif.Value  := (Defaults["NotificaAvvio"] = "1")
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

    ; separatore + nota
    g.AddText("x22 y" (yEnd + 44) " w326 0x10", "")
    g.SetFont("s9", "Segoe UI")
    g.AddText("x22 y" (yEnd + 56) " w326 c808080",
        "Per cambiare i tasti usa 'Impostazioni...' nel menu del tray.")

    g.SetFont("s9", "Segoe UI")
    btn := g.AddButton("x258 y" (yEnd + 104) " w90 Default", "OK")
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
