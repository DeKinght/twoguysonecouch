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

## Mapa i modele
Host wybiera mapę w lobby (lista `Net.LEVELS`: Blok albo Dom). Mebel do noszenia: wstaw `grabbable.tscn`,
ustaw `model` (plik .glb z `assets/models/furniture/`), `item_name`, `mass`, `value`. Modele Kenney
mają skalę ~1:2, stąd domyślne `model_scale = 2`.
