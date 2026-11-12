# Diseño de juego de ALUX

Mecánicas, progresión y transformaciones. Los números exactos del combate actual están en
[combate.md](combate.md) y en `game/scripts/shared/combat_def.gd`; aquí va el porqué y lo que viene.

## Pilares

| Pilar | Qué significa al diseñar |
| --- | --- |
| **Juntos o nada** | Todo lo importante pide cooperar: abrir, resistir, vencer. Escala de 1 a 4 jugadores sin dejar de pedirlo. |
| **Cambiar de forma es la jugada** | Cada forma resuelve cosas que las otras no. La estrategia es quién toma cuál, y cuándo. |
| **Recordar, no destruir** | Los enemigos son Olvidados. Purificarlos es mejor que romperlos y el juego lo premia. |
| **Se entiende sin leer** | Objetivo siempre visible, avisos de ataque claros, una tecla para tocar y hablar. |
| **La red manda** | El servidor decide movimiento, daño, progreso e historia. El cliente sólo presenta. |

## Bucle de juego

1. **Escuchar:** un personaje o una escena dice qué pasa y qué hace falta.
2. **Explorar:** encontrar los puntos del acertijo (brújula, objetivo).
3. **Coordinarse:** resolver el acertijo cooperativo que abre el camino.
4. **Resistir:** un encuentro que escala con el grupo.
5. **Vencer al guardián** del capítulo (jefe).
6. **Vincularse:** recompensa narrativa y persistente; se abre el siguiente lugar.

Una partida del Capítulo I completo debe durar 20–30 minutos.

## Formas

Las formas son vínculos con espíritus guardianes ([STORY_BIBLE.md](STORY_BIBLE.md)). Todas las puede
tener todo jugador: no son clases fijas.

| Forma | Movimiento | Combate | Exploración | Aporte al grupo | Estado |
| --- | --- | --- | --- | --- | --- |
| **Alux** | 5.2 m/s, salto corto | Chispa de jade a distancia, esquiva | **Tocar**: hablar, purificar, encender el brasero | Cura al grupo (brasero y purificación) | En el juego |
| **Balam** | 8.4 m/s, salto alto | Garras, zarpazo cargado que aturde, salto ofensivo en área | Llega a lo alto y a lo lejos | Abre huecos: aturde y empuja | En el juego |
| **Guardián del Cenote** (Áayin) | Lento en tierra, veloz en el agua; se sumerge | Coletazo en arco, embestida bajo el agua | Bucear, mover el nivel del agua, llevar a un compañero | Rescate y transporte por agua | Planeado (0.6) |
| **Guardián de Obsidiana** (Tuunich) | Lento; no lo empujan | Golpe pesado, escudo que cubre a quien esté detrás | Mover bloques, romper barreras, aguantar corrientes | Protege y sostiene mecanismos | Planeado (III) |
| **Ave del Viento** (Toh) | Planea; sube con corrientes | Picado, ráfaga que desplaza | Alcanzar alturas, llevar semillas o llaves | Ve y marca objetivos desde arriba | Planeado (IV) |
| **Kukulkán** | Vuelo de serpiente | Forma final | Sólo existe cuando los cuatro actúan a la vez | Culminación cooperativa | Planeado (V) |

**Regla técnica:** una forma nueva es una entrada en `FORMS` con sus tres habilidades (primaria,
secundaria, especial) por *tipo* de habilidad. Si una forma necesita un tipo que no existe (bucear,
planear, escudo), se añade ese tipo a la simulación compartida con sus pruebas de invariantes.

## Enemigos

| Enemigo | Papel | Cómo se lee | Estado |
| --- | --- | --- | --- |
| Guardián de piedra | Lento, golpe en área, resiste las chispas | «!» y marca en el suelo antes del golpe | En el juego (modelo provisional) |
| Criatura corrompida | Rápida, embiste, débil a las chispas, **purificable** | Anillo de jade y «F» cuando ya se puede purificar | En el juego (modelo provisional) |
| **Nojoch Tuunich**, el Guardián Dormido | Jefe del Capítulo I | Ver abajo | Diseñado |

En la historia, los dos enemigos actuales son los guardianes y los animales del claro tocados por el
Silencio: por eso algunos se purifican y los de piedra sólo se detienen.

## Jefe del Capítulo I: Nojoch Tuunich (diseño)

Un coloso de piedra dormido en el patio del santuario. No es malvado: olvidó a quién cuida.
Se le vence haciéndole recordar. Reutiliza sistemas que ya existen.

| Fase | Qué hace él | Qué tiene que hacer el grupo | Sistemas que reutiliza |
| --- | --- | --- | --- |
| **1. Olvido** | Golpes lentos en área con aviso; llama criaturas corrompidas. Su pecho está cubierto por el Silencio. | Purificar criaturas cerca de él: cada una devuelve luz a un glifo del pecho. Con los glifos encendidos, queda expuesto. | IA de enemigos, avisos, purificación |
| **2. Furia** | Levanta los brazos y descarga golpes en cadena. | Repartirse: unos pisan las **anclas** (altares del patio, tantos como jugadores menos uno) para sujetarlo; los demás golpean el corazón. Balam hace el daño; el alux sostiene y cura. | Altares de presión, zarpazo cargado, aturdimiento |
| **3. Recuerdo** | Cae de rodillas, casi sin fuerza. | **Todos** lo tocan (F como alux) a la vez. Recuerda, y se queda como guardián del claro. | Purificación, regla de "todos a la vez" |

- **Escala:** vida, criaturas y anclas según los jugadores conectados, como la emboscada.
- **Derrota:** si cae todo el grupo, el jefe vuelve a dormirse y se reintenta, como ya ocurre.
- **Un jugador solo:** las anclas se quedan pisadas unos segundos al soltarlas.
- **Sin trampas:** fases, glifos y anclas los decide el servidor.

## Objetivos e historia

El progreso narrativo de una sala son **banderas** que guarda el servidor y viajan en el estado del
mundo. El cliente elige con ellas el objetivo, la marca de la brújula y qué dice cada personaje.

| Momento | Objetivo en pantalla | Cómo se avanza |
| --- | --- | --- |
| `llamado` | Habla con Chiich Yaxché | Un jugador termina de hablar con ella estando a su lado |
| `altares` | Pisa un altar / Pisen N altares | Regla actual de los altares |
| `emboscada` | Quedan N enemigos | Regla actual |
| `derrota` | El santuario se selló de nuevo | Automático tras unos segundos |
| `liberado` | Santuario liberado | — (seguirá el jefe en 0.3) |

Hablar con la abuela **no es obligatorio**: quien ya conoce el juego puede ir directo a los altares.
Los personajes no tienen colisión y su posición y alcance están en `shared/story_def.gd`.

## Progresión

| Qué | Dónde se guarda | Estado |
| --- | --- | --- |
| Formas vinculadas | Perfil del jugador (`unlocks`) | En el juego (Alux y Balam de inicio) |
| Sello del Claro | Perfil (`rewards_ledger`), una vez por jugador | En el juego |
| Plumas de Kukulkán | Perfil; una por capítulo | Planeado (0.4): el sello pasa a ser la Pluma de Jade |
| Avance del capítulo | Perfil (`rewards_ledger`): «El llamado de la abuela» al hablar con ella | En el juego (0.2). La sala nueva aún empieza la historia desde el principio |

## Controles

| Acción | Tecla |
| --- | --- |
| Moverse · saltar | W A S D · Espacio |
| Mirar | Ratón · Q / E · R recentra |
| Primaria · secundaria · especial | Clic · clic derecho · F |
| **Tocar y hablar** | F (junto a un personaje, F siempre es hablar) |
| Formas | 1 Alux · 2 Balam |
| Diálogo | Enter, F o clic avanza · Esc cierra |
| Cinemática | Propia: Enter o Esc la omite · Compartida: Enter vota, se omite por mayoría |
| Menú · ayuda | Esc o P · H |

Sin mando ni pantalla táctil por ahora.

## Límites que condicionan el diseño

- **Navegador:** sin texturas, pocos materiales; cada efecto nuevo se mide. Sin datos todavía de
  tarjeta gráfica ([rendimiento.md](rendimiento.md)).
- **Servidor:** una instancia de 512 MB para portal, API y juego.
- **Un solo mapa:** varias zonas requieren trabajo de arquitectura (Alpha 0.5).
- **Diálogos:** lineales; todavía no hay respuestas a elegir ni voces.
