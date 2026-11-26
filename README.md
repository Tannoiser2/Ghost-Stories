# Ghost Stories — versione digitale

Il gioco cooperativo di Antoine Bauza (Repos Production, illustrazioni di Pierô) in Godot 4.7,
con la grafica originale presa dal modulo Tabletop Simulator e tutti i testi in italiano.

Si gioca su https://tannoiser2.github.io/Ghost-Stories/ (e nella ludoteca).

## Che cosa c'è

- **Gioco base completo**: 55 carte fantasma, 10 incarnazioni di Wu-Feng, 9 tessere del villaggio,
  le 4 plance su entrambi i lati (8 poteri), Buddha, Yin-Yang, Cerchio di Preghiera, mantra, dadi catturati,
  plance neutre e possedute, segnalini potere, morte e Cimitero, punteggio finale.
- **Quattro livelli**: Iniziazione, Normale, Incubo, Inferno; da 1 a 4 Taoisti (con le regole per 1, 2 e 3).
- **Compagni guidati dal computer** (`scripts/ia.gd`): valutano la minaccia di ogni fantasma, calcolano la
  probabilità esatta di esorcizzarlo con i dadi e i segnalini e scelgono movimento, azione, aiuti e premi.
- **Online con Firebase** (progetto condiviso della ludoteca, radice `ghoststories`): chi ospita apre una stanza
  con codice e QR, gli amici entrano e giocano il proprio Taoista; i posti vuoti li gioca il computer.
- **Salvataggio** a ogni mossa sul dispositivo e una copia su Firebase (`ghoststories/salvataggi/<uid>`).
- Tavolo 2D che si sposta, si ingrandisce e si ruota con mouse, rotella o con le dita (anche su iPad).

- **Espansione White Moon**: villici e famiglie con maledizioni e ricompense, Portale, Su-Ling, Cristalli di Luna,
  ricettacoli e Barriera Mistica, 8 artefatti, Scuola di Kung-Fu, 10 fantasmi e 6 incarnazioni nuove.
- **Tavolo 3D** (predefinito, si passa al 2D con un tasto): miniature dei Taoisti colorate per plancia, spettri
  trasparenti, incarnazioni con fiamme e luce, dadi Tao e della maledizione lanciati sul tavolo, fumo, scintille,
  colonne di luce, lanterne e nebbia; si ruota e si ingrandisce anche con le dita.
- IA con pesi tarati da migliaia di partite automatiche (`tests/taratura.gd`, verifica in `tests/convalida.gd`).

- **Espansione Black Secret**: Wu-Feng giocato da una persona, da un amico online o dal computer (indulgente o
  spietato); demoni che scavano le catacombe in cerca delle tre urne, Ombra di Wu-Feng, scale, scheletri,
  piramide delle maledizioni, Mantra di Sangue, Fratelli di Sangue, Calligrafo, 10 fantasmi e 5 incarnazioni nuove.
  Si può giocare insieme a White Moon. Le carte dei Mantra di Sangue non sono nel modulo TTS: i loro testi sono scritti a parte.

## Struttura

| File | Che cosa fa |
|---|---|
| `scripts/motore.gd` | tutte le regole: stato salvabile in JSON, una pila di compiti che si ferma a ogni scelta |
| `scripts/ia.gd` | le decisioni dei Taoisti guidati dal computer |
| `scripts/partita.gd` | lo schermo di gioco: schede, scelte, dadi, diario, online |
| `scripts/tavolo.gd` | il tavolo con villaggio e plance, tocchi e gesti |
| `scripts/main.gd` | menu, impostazioni, stanze online |
| `assets/dati/fantasmi.json` | i dati di ogni carta (colore, resistenza, effetti) e i testi di tessere e poteri |
| `tools/prepara_grafica.py` | estrae la grafica dal modulo TTS e scrive i nomi italiani sulle carte |
| `tests/partite.gd` | partite automatiche a tutti i livelli (l'IA gioca tutti i Taoisti) |
| `tests/schermate.gd` | schermate di prova a varie risoluzioni |

## Prove

```
godot --headless --import
godot --headless --script tests/partite.gd -- 10
xvfb-run godot --rendering-driver opengl3 --script tests/schermate.gd -- /tmp/schermate 1920 1080
python3 tools/controlla_glifi.py
tools/costruisci_web.sh
```

## Pubblicazione

Il workflow `Pubblica` parte a mano (Actions → Pubblica → Run workflow) oppure con un commit che contiene
`[pubblica]` nel messaggio. La ludoteca privata su Cloudflare prende il pacchetto da sola.
