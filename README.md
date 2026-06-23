# Volume & Power Tray

Piccola utility per Windows che resta nel **system tray** e permette di controllare
**volume**, **sospensione** e **spegnimento** del PC tramite hotkey globali personalizzabili.

Scritta in [AutoHotkey v2](https://www.autohotkey.com/) e compilata in un eseguibile
autonomo (non richiede AutoHotkey installato sul PC di destinazione).

## Funzioni

- 🔊 **Volume su / giù** (mostra la barra volume di Windows, oppure cambio silenzioso)
- 😴 **Sospensione (sleep)** con finestra di **conto alla rovescia** e pulsante per annullare
- ⏻ **Spegnimento** con conto alla rovescia, icona di avviso e pulsante per annullare
- ⚙️ **Finestra Impostazioni**: cambia tasti e opzioni senza ricompilare (con "premi per assegnare")
- 🔔 Notifica all'avvio e finestra "Mostra hotkey"
- 🚀 Opzione **Avvia con Windows** (crea un collegamento nella cartella Esecuzione automatica)
- ☕ **Tieni sveglio** (stile PowerToys Awake): impedisce la sospensione e, a scelta, lo spegnimento dello schermo — indefinitamente o per un intervallo (30 min / 1 / 2 / 4 / 8 / 12 ore)

## Hotkey predefiniti

| Tasto | Azione | Conferma |
|-------|--------|----------|
| `F11` | Volume su | — |
| `F10` | Volume giù | — |
| `F1`  | Sospendi (sleep) | conto alla rovescia |
| `F2`  | Spegni | conto alla rovescia |

Tutti modificabili da **menu del tray → Impostazioni…** (o nel file `VolumePowerTray.ini`).
Modificatori nelle combinazioni: `^` = Ctrl, `!` = Alt, `+` = Shift, `#` = Win
(es. `^!Up`, `#PgUp`).

## Uso

Avvia **`VolumePowerTray.exe`**: comparirà un'icona nel tray (vicino all'orologio).
Clic destro sull'icona per il menu.

> Alla prima esecuzione viene creato `VolumePowerTray.ini` accanto all'eseguibile con i
> valori predefiniti. L'exe deve poter scrivere nella propria cartella, quindi evita
> `C:\Program Files` (sola lettura): va bene Desktop, Documenti o una chiavetta USB.

> Essendo un eseguibile non firmato, la prima volta Windows SmartScreen potrebbe avvisare:
> *Ulteriori informazioni → Esegui comunque*.

## Compilazione

Richiede [AutoHotkey v2](https://www.autohotkey.com/) e il compilatore **Ahk2Exe** installati.
Poi basta eseguire:

```
Compila.bat
```

Lo script chiude l'eventuale istanza in esecuzione, compila `VolumePowerTray.ahk` in
`VolumePowerTray.exe` (con l'icona `VolumePowerTray.ico` incorporata) e offre di riavviarlo.

## Etichette per la tastiera

`EtichetteTasti.html` è una pagina stampabile con piccole icone colorate (8×8 mm) da
ritagliare e fissare sui tasti con dello scotch trasparente. Apri il file nel browser e
stampa **a grandezza reale (100%)**.

## File del progetto

| File | Descrizione |
|------|-------------|
| `VolumePowerTray.exe` | Il programma (eseguibile autonomo) |
| `VolumePowerTray.ahk` | Codice sorgente AutoHotkey v2 |
| `VolumePowerTray.ico` | Icona dell'applicazione |
| `Compila.bat` | Ricompila il sorgente in eseguibile |
| `EtichetteTasti.html` | Etichette stampabili per i tasti |
| `VolumePowerTray.ini` | Configurazione locale (generata in automatico, non versionata) |
