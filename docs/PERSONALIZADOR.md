# Personalizador 3D del alux

Alpha 0.4. El jugador viste a su alux viendo **el modelo real del juego**, lo guarda en su perfil y
los demás lo ven igual. Prueba: `npm run test:customizer`
([tests/e2e/customizer.ts](../tests/e2e/customizer.ts)).

## Qué se puede elegir

| Familia | Opciones |
| --- | --- |
| Color de la túnica | 12 |
| Color secundario (ribetes, capa, faja, pañuelo, correa del morral) | 10 |
| Tono de piel | 5 |
| Vestimenta | Túnica · Capa corta · Faja con flecos · Bordado |
| Tocado | Sombrero de palma · Penacho · Flor de mayo · Sin tocado · Diadema de plumas · Pañuelo · Corona de hojas |
| Accesorio | Ninguno · Morral · Sonaja · Caracol · Farol de luciérnagas |
| Amuleto | Ninguno · Colgante de jade · Concha · Espejo de obsidiana · Collar de semillas |

El alux de siempre (túnica, sombrero de palma, morral y colgante de jade) es el aspecto inicial:
quien no toque nada se ve como hasta ahora. Las piezas son diseños propios, de fantasía cotidiana;
no hay insignias ceremoniales ni símbolos religiosos reales. Hojas con todas las opciones:
[art/propuestas/alux_personalizacion/](../art/propuestas/alux_personalizacion/README.md).

## Cómo se usa

- **Desde el portal**: «Personalizar en 3D» abre el juego en modo vestir (`/alux`), sin sala: el
  alux aparece en la plaza del Claro.
- **Dentro de una sala**: Menú → «Personalizar mi alux», fuera de combate. La cámara gira alrededor
  del alux donde está; si empieza una emboscada o una escena, se cierra sin guardar.
- **Cámara orbital**: arrastrar gira y sube o baja, la rueda (o las flechas, o el gesto de pinza)
  acerca; cuerpo completo siempre a la vista. Se puede ver en reposo, corriendo o saltando.
- «Al azar», «Deshacer cambios», «Guardar».

## Cómo viaja y quién manda

1. El panel sólo ofrece **lo que el modelo trae** (busca cada nodo en `alux.glb`).
2. Guardar es una llamada a la API (`PUT /v1/me/character`). La API sólo acepta **índices de los
   catálogos** ([domain.ts](../packages/shared-contracts/src/domain.ts)); cualquier otra cosa es un
   error 400. Se guarda en la columna `look` (migración sólo aditiva).
3. Al entrar a una sala, el aspecto va dentro del **ticket firmado** por la API. El servidor de
   juego no acepta el aspecto de ningún cliente.
4. Si el jugador se cambia con la partida en marcha, el cliente sólo avisa (`look`); el servidor
   **relee el aspecto de la API** y lo reparte a la sala. Los demás lo ven sin recargar.

Los catálogos están en dos sitios (contrato y `game/scripts/shared/look_def.gd`); una prueba
(`npm run test:look -w @alux/tests`) falla si dejan de coincidir.

## Comprobado

En Chromium, automatizado: el portal abre el modo vestir con el aspecto del perfil; elegir cambia
las piezas que el modelo dibuja (se comprueban los nodos visibles, uno por familia); la cámara gira
y se acerca; guardar llega al perfil y persiste al volver; otro jugador en la misma sala dibuja ese
aspecto; cambiarse dentro de la sala se replica sin recargar. API: aspectos fuera del catálogo
rechazados y aspecto conservado cuando el editor sencillo del portal no lo manda.

## Sin comprobar y límites

- **Nadie lo ha usado con una tarjeta gráfica ni a mano**: los colores y los tonos de piel se han
  mirado en capturas de render por software.
- La capa se arruga en los hombros con los brazos en alto (salto, esquiva, nado).
- Los accesorios del cinto se ven sobre todo desde atrás (que es donde está la cámara del juego).
- Balam no cambia con el aspecto (sólo el color del collar, como antes).
- El editor sencillo del portal sigue cambiando nombre y color; su dibujo 2D no muestra las piezas
  nuevas.
- La versión publicada (0.3.1) no tiene nada de esto; llegará con la Alpha 0.4.
