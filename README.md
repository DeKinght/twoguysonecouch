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

## Generator miasta (`scripts/levels/world_generator.gd`)
Po przyjęciu zlecenia na komputerze host losuje ziarno (`JobComputer.world_seed`) i rozsyła je graczom - każdy
buduje identyczne miasto wokół Siedziby. Siatka modułów 9 x 9 m (kafel drogi = budynek z podstawą):
linie ulic co 36/45/54 m, 4 przecznice w każdą stronę; losowo usuwane odcinki ulic (sieć zawsze spójna, bez
ślepych uliczek); kafle skrzyżowań dobierane do wylotów; budynki frontem do ulic, w głębi kwartałów parki
i parkingi; obrzeże zabudowane wysokimi budynkami + niewidzialne ściany. Kwartał Siedziby (budynek + 10 m)
jest zawsze otoczony ulicami, wjazd do garażu łączy się z ulicą przy x = -14,5; wokół działki płot z przerwą
na wjazd. Dom docelowy (z meblami do zabrania) w losowym kwartale >110 m od Siedziby, ze słupem światła
i napisem "ZLECENIE". Modele rysowane przez MultiMesh (kilkadziesiąt węzłów zamiast tysięcy).

### Dzielnice, horyzont, dom klienta
- Każdy moduł miasta należy do dzielnicy: przedmieście (Kenney Suburban), śródmieście (Kenney Commercial + kamienice
  KayKit) albo przemysł (Kenney Industrial). Śródmieście i przemysł mają losowe "centra" po przeciwnych stronach
  Siedziby, a granice wyznacza płynny szum (`FastNoiseLite`) - przejścia są nieregularne i mieszane.
  Działki jedno- lub dwumodułowe (większe domy, hale, biurowce), wnętrza kwartałów zależne od dzielnicy
  (parki / ogródki kawiarni / place z kontenerami i zbiornikami), kominy przy halach.
- Krawędź mapy: za pierścieniem budynków trzy pierścienie dalekiej zabudowy (Kenney low-detail, matowe, w kolorze
  mgły) przetykane lasem, wzgórza na horyzoncie, mgła z perspektywą powietrzną i niebo w kolorze mgły.
- Dom klienta (`scripts/levels/target_house.gd`): dom z Kenney Suburban (building-type-h) z wyciętym skrzydłem drzwi,
  przezroczystymi szybami i wnętrzem: salon z aneksem kuchennym, sypialnia za ścianką działową, drzwi wejściowe
  i do sypialni otwierane na E, lampy, 17 mebli do zabrania. Dom losuje się na przedmieściu.


## Wydajność
- Ustawienia → **Limit klatek** (30/60/90/120/144/bez limitu, domyślnie 60). **F3** w grze: licznik FPS,
  liczba rysowanych obiektów, wywołań rysowania i trójkątów.
- Miasto rysowane w kwadratach 72 x 72 m (panorama 150 x 150 m), więc kwadraty poza kadrem i poza warstwami
  cienia są pomijane, a dalekie kwadraty używają automatycznych LOD-ów z importu. Drobiazgi (ławki, hydranty,
  auta, kontenery, latarnie...) płynnie znikają za 90-190 m (dithering, już we mgle); budynki nigdy.
  Meble do noszenia nie są tym objęte.
- `scripts/core/render_tuning.gd`: słońce z 2 warstwami cienia do 80 m i bez drobiazgów z wnętrz budynków
  (warstwa renderowania 2 - dach i tak je zasłania); lampy wygaszają się z odległości (cienie lamp bez zmian).
- Różnorodność zabudowy: budynek nie powtarza modelu dwóch ostatnich sąsiadów z tej samej pierzei, dostaje losową
  paletę kolorów (variation-a/b/c z paczek Kenney), skalę, cofnięcie od ulicy, przesunięcie w bok i lekki obrót
  (najmniej w śródmieściu, najwięcej na przedmieściu). Część działek zostaje pusta (ogród / parking / plac),
  przed cofniętymi domami czasem rośnie żywopłot.
- Kamera zza auta (V) nie wchodzi w budynki: kula sprawdza drogę od auta do kamery, a kamera staje tuż przed
  przeszkodą (przybliża się od razu, oddala płynnie).
- Pierścień na skraju miasta: mieszanka kamienic KayKit (różna wysokość) i budynków dzielnicy, które stoją
  przed nim, z lekkim rozrzutem i bez powtórek sąsiadów. Panorama za murem dopasowana do dzielnicy: tuż za
  murem prawdziwe budynki tej dzielnicy, dalej bryły o wysokościach jak w mieście (przedmieście 6-10 m,
  przemysł 8-16 m, śródmieście 14-34 m), na przedmieściach więcej drzew.

### Krawędź miasta (`scripts/levels/city_edge.gd`)
Każdy odcinek obwodu zależy od dzielnicy, która do niego dochodzi (odcinki min. 4 moduły):
- przemysł -> **port**: nabrzeże z pachołkami i żółtą krawędzią, kontenery, suwnice nad wodą, statek z kontenerami
  przy dłuższych odcinkach, woda (shader `shaders/water.gdshader`), daleki brzeg ze wzgórzami;
- śródmieście -> **obwodnica**: estakada z ekranami akustycznymi, barierami i filarami, ruch aut
  (`highway_traffic.gd`), pod nią parkingi, zieleń i billboardy; na końcach odcinka skręca od miasta
  i znika w tunelu we wzgórzu (albo we mgle);
- przedmieście -> **wzgórza**: ogródki działkowe (altanki, grządki, płotki), łąki, potem zalesione wzgórza.
Część wylotów ulic jest zamknięta (zapora, pachołki, tablica) i prowadzi dalej jako droga leśna / asfalt pod
estakadą / brama portu. Teren to jedna siatka z kolorami wierzchołków (dolina zamknięta pasmem gór),
las daleko to MultiMesh prostych drzewek bez cieni. Statyczne bryły (krawędź, płoty, place) trafiają do
zbiorczych siatek - jedna na kwadrat 72 m (`WorldGenerator._merge_box`).
- Estakada to jedna ciągła bryła wyciągnięta wzdłuż trasy (bez szczelin), osobno na każdym boku miasta (min. 8 modułów),
  na końcach odbija od miasta łukiem o promieniu do 70 m. Port: kontenerowiec z Kenney Watercraft przy nabrzeżu,
  statki na redzie, holownik i boje. Parkingi: rzędy miejsc w śródmieściu i pod estakadą, auta na podjazdach
  przed niektórymi domami (bez pojedynczych aut na skwerach).

