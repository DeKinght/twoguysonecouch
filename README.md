# Two Guys One Couch

Godot 4.3+ (standardowy, nie .NET). Otwórz `project.godot` w Godot Project Manager (Import) i wciśnij F5.

## Struktura

```
project.godot
scenes/
  player/player.tscn      Gracz (CharacterBody3D + Head + Camera3D + Grabber + HUD)
  items/grabbable.tscn    Uniwersalny przedmiot (RigidBody3D); wygląd z `size` i `color`
  levels/street.tscn      Osiedle: ulica, 3 domy (w tym piętrowy ze schodami), ciężarówka = strefa załadunku
  levels/house.tscn       Mapa testowa: dom (salon, kuchnia, sypialnia) + ciężarówka z rampą
  levels/test_room.tscn   Poligon: podłoga, ściana z wąskimi drzwiami, 4 przedmioty
assets/models/furniture/  Kenney Furniture Kit (CC0), modele .glb
assets/models/building/   Kenney Building Kit (CC0) - ściany, schody domów
assets/models/city/       KayKit City Builder Bits (CC0) - ulica, kamienice, auta
assets/models/nature/     KayKit Forest Nature Pack (CC0) - drzewa, krzaki, kamienie, trawa
scripts/
  core/input_setup.gd     Autoload, rejestruje klawisze
  player/player.gd        Ruch, kamera, kucanie
  player/grabber.gd       Chwytanie sprężyną (serce gry)
  items/grabbable.gd      Dane przedmiotu + lista trzymających; `model` = .glb, kolizja liczy się sama
  levels/street_level.gd  Osiedle: tworzy zlecenie (JobManager) ze strefą $Truck/LoadZone
  levels/static_prop.gd   Nieruchomy model (ściany, zabudowa) z kolizją z siatki
ui/hud.gd                 Celownik i podpowiedź
```

## Sterowanie
WASD, Shift sprint, Spacja skok, Ctrl/C kucanie, LPM (trzymaj) chwyt, kółko myszy odległość, B popchnij kumpla, Esc menu (ustawienia: głośność, czułość, klawisze), F11 pełny ekran.

Auto: E patrząc na drzwi kabiny = wsiądź (kierowca po lewej, pasażer po prawej), E patrząc na tył paki = otwórz/zamknij
(otwarte drzwi robią za rampę), E patrząc na półkę w pace = usiądź (2 miejsca). W aucie: W gaz, S hamulec / wsteczny,
A/D skręt, Spacja ręczny, V kamera 1./3. osoby, E wysiądź.

## Auto (`scenes/vehicles/van.tscn`, `scripts/vehicles/van.gd`)
Dostawczak z Kenney Car Kit (`delivery.glb`, skala 1,84) na `VehicleBody3D`: napęd na tył, 1,8 t, ~0-40 km/h w 6 s,
hamowanie ~6,5 m/s², maks. 70 km/h. Kabina ma wnętrze (fotele, deska, kierownica obracająca się z kołami) i przezroczyste
szyby - domyślnie jedzie się z widoku kierowcy, V przełącza na kamerę zza auta. Dźwięki w `assets/audio/van/`:
rozruch, bieg jałowy i jazda (wysokość z obrotów 4-biegowej "skrzyni"), zmiana biegu, syk hamulca po zatrzymaniu,
wsiadanie/wysiadanie, drzwi paki. Fizykę liczy host, kierowca wysyła mu tylko wejście; miejsca (`net_seats`) i drzwi
też zmienia host. Paka (`cargo_zone`) to strefa załadunku zlecenia; szkody przedmiotów w pace, których nikt nie trzyma,
idą na konto kierowcy. Potrącenie przy > 3 m/s przewraca gracza.

## Mapa i modele
Host wybiera mapę w lobby (lista `Net.LEVELS`). Mebel do noszenia: wstaw `grabbable.tscn`,
ustaw `model` (plik .glb z `assets/models/furniture/`), `item_name`, `mass`, `value`. Modele Kenney
mają skalę ~1:2, stąd domyślne `model_scale = 2`.

## Postacie (`scripts/player/character_model.gd`)
3 oryginalne postacie tragarzy: Bartek (polówka, czapka, broda), Ola (odblaskowa kurtka, kucyk) i Dawid
(ogrodniczki, okulary, kręcone włosy). Siatki (`assets/characters/*.res`, ~60 tys. trójkątów) są wyrzeźbione
skryptem `tools/characters/sculpt.py` (miękko łączone kształty + marching cubes, płynne wagi kości na stawach)
i zamienione na zasoby Godota przez `tools/characters/build_meshes.gd`. Szkielet: 17 kości (biodra, kręgosłup,
klatka, szyja, głowa, ramiona/przedramiona/dłonie, uda/łydki/stopy). Animacje: idle, walk, run, carry,
carry_walk, crouch, crouch_walk, sit, jump, fall. Host losuje każdemu graczowi postać przy spawnie (bez powtórek).

Przebudowa postaci po zmianie w sculpt.py:
```
python tools/characters/sculpt.py /tmp/chars        # wymaga numpy, scikit-image, pyfqmr
godot --headless --path . -s tools/characters/build_meshes.gd -- /tmp/chars
```

## Komputer ze zleceniami (Siedziba)
Lewy monitor na biurku (`scripts/interact/job_computer.gd`, ekran `ui/computer_screen.gd`). E = kamera podjeżdża
do monitora i otwiera się giełda zleceń; Esc lub "Wyloguj" zamyka. Z komputera korzysta jedna osoba naraz
(stan trzyma host) - pozostali widzą "Komputer zajęty". Zlecenia są w `JobComputer.JOBS` (tytuł, opis, obrazek,
gwiazdki 0-5). Na czas korzystania gra używa własnego, większego kursora.
