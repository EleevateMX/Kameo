# Nojoch Tuunich, el Guardián Dormido

Diseño del primer jefe de ALUX (Alpha 0.3). **Propuesta para tu aprobación:** nada de esto está
programado todavía y no se ha gastado ningún crédito de Kling en él. Resumen del capítulo y de las
formas: [GAME_DESIGN.md](GAME_DESIGN.md) · Historia: [STORY_BIBLE.md](STORY_BIBLE.md) ·
Cinemáticas: [CINEMATICS.md](CINEMATICS.md).

## Qué es

Un coloso de caliza tallada que duerme sentado en el patio del santuario desde antes de que hubiera
aluxes. Guardaba la primera pluma de Kukulkán. El Silencio no lo corrompió: le hizo **olvidar a
quién cuida**, y al despertar ve intrusos. No se le mata: se le hace **recordar**.

Por eso su barra no es de vida sino de **Silencio**: baja cuando el grupo le devuelve memoria, no
cuando le pega.

| | |
| --- | --- |
| Tamaño | 3.4 m sentado, 5 m de pie (un alux mide 1.1 m) |
| Aspecto | Bloques de caliza encajados, cabeza ancha con tocado escalonado, cuatro glifos de jade en el pecho, un corazón de cristal en la espalda, musgo y raíces. Vetas magenta mientras está olvidado |
| Dónde | Patio del santuario (12 × 12 m) y, desde la fase 2, la explanada de delante |
| Cuándo | Al entrar el grupo al patio tras superar la emboscada |
| Duración objetivo | 5–7 minutos con cuatro jugadores; 8–10 uno solo |

## El combate pide repartirse

| Lo que hace falta | Sólo lo puede hacer | Con qué |
| --- | --- | --- |
| Devolver la memoria a una criatura | El alux | Tocar (F) |
| Dejar a una criatura lista para purificar sin romperla | Balam | Zarpazo cargado: aturde |
| Sujetar al guardián | El alux, quieto sobre un ancla | Pisar el altar |
| Alcanzar el corazón de la espalda, a 3 m de altura | Balam | Salto alto y salto ofensivo |
| Cubrirse de la lluvia de piedra y curar al grupo | El alux | Brasero y purificación |
| Despertarlo del todo | Todos como alux, a la vez | Tocar (F) |

Nadie queda atado a una forma: cualquiera cambia con 1 y 2 en cualquier momento.

## Fases

### 1. Olvido — en el patio

El guardián se levanta y pelea despacio. Su pecho está apagado.

| Ataque | Aviso | Efecto | Cómo se responde |
| --- | --- | --- | --- |
| **Golpe de losa** | Levanta el puño 1.2 s; círculo en el suelo (3.5 m) | Daño alto. **Rompe las losas**: esa zona queda hundida 12 s y quien cae recibe daño y vuelve al borde | Salir del círculo; después, rodear el hueco |
| **Barrido** | Gira el torso 0.9 s; abanico de 140° | Daño medio y empujón | Esquiva del alux o salto de Balam |
| **Llamada del Silencio** | Golpea el suelo con las dos manos | Salen criaturas corrompidas de los muros (2 a 4 según el grupo) | Ver abajo |

**Cómo avanza:** cada criatura **purificada a menos de 6 m de él** enciende uno de los glifos del
pecho. Balam las aturde y las acerca; el alux las toca. Romperlas no cuenta. Con los glifos
encendidos (2 jugando solo, 4 con cuatro) el Silencio pierde un tercio y empieza la fase 2.

### 2. Furia — el escenario cambia

El guardián arranca los muros del patio: **el lado oeste del santuario se derrumba** y el combate
sale a la explanada, donde brotan del suelo **anclas** (altares de presión) y columnas de piedra.

| Ataque | Aviso | Efecto | Cómo se responde |
| --- | --- | --- | --- |
| **Columnas** | El suelo tiembla en tres puntos | Tres pilares suben del suelo y se quedan: estorban y dan refugio | Apartarse; usarlos después |
| **Lluvia de piedra** | Alza los brazos 2 s; el cielo se oscurece | Caen piedras en toda la explanada durante 4 s | Ponerse **detrás de un pilar** |
| **Embestida** | Rasca el suelo 1.5 s; línea ancha | Corre en línea recta y destroza los pilares que toca | Apartarse de la línea. Si se le hace embestir **contra un ancla**, queda aturdido 5 s |
| Golpe de losa y Barrido | Como antes, más rápidos | | |

**Cómo avanza:** mientras está aturdido, los alux pisan las anclas (tantas como jugadores menos una;
una jugando solo, que se queda pisada 6 s al soltarla) y salen cadenas de jade que lo sujetan de
rodillas. Sólo entonces el **corazón de la espalda** queda expuesto, y sólo Balam llega. Cada vez que
se le suelta, el Silencio baja otro tramo. Tres veces y empieza la fase 3.

### 3. Recuerdo

Cae de rodillas en el centro. Ya no ataca: el Silencio sale de él en una última oleada de criaturas
que van a por quien esté tocándolo.

**Cómo termina:** **todos los conectados**, como alux, lo tocan (F) a la vez durante 3 s, uno en cada
glifo del suelo que rodea sus manos. Quien recibe un golpe se suelta; por eso alguien tiene que
aguantar a las criaturas hasta el último momento y volver a tiempo. Jugando solo, basta sostener el
toque 4 s seguidos.

Las vetas magenta se apagan, los glifos se encienden y el guardián recuerda.

## Reglas generales

| Tema | Regla |
| --- | --- |
| Escala | Silencio, criaturas, glifos y anclas según los conectados, como la emboscada. El daño usa la misma escala que ya existe (×0.6 / ×0.8 / ×1 / ×1) |
| Derrota | Si cae todo el grupo, el guardián vuelve a sentarse y se dormita. Se reintenta desde el principio de la **fase alcanzada**, no desde cero |
| Caídas | Reaparecer tarda 8 s, como en la emboscada, junto a la entrada del patio |
| Quién decide | El servidor: fases, glifos, anclas, huecos del suelo, muros caídos y pilares. El cliente sólo dibuja |
| Trampas | Ningún mensaje del cliente puede saltarse una fase, encender un glifo ni tocar el Silencio |
| Sin atascos | Ninguna fase depende de que el jefe haga un ataque concreto: las criaturas y la embestida vuelven cada cierto tiempo |
| Otra ronda | Tras vencerlo, la sala puede votar otra ronda como hoy; el jefe vuelve a dormirse |

## Qué hay que construir

| Pieza | Reutiliza | Nuevo |
| --- | --- | --- |
| El jefe como entidad | IA de enemigos, avisos de ataque, aturdimiento, escala de daño | Máquina de fases, ataques con patrón, barra de Silencio |
| Glifos y purificación | Purificación de criaturas | Contar sólo las que ocurren cerca de él |
| Anclas | Altares de presión, la regla de «tantos como jugadores» | Cadenas, ventana de corazón expuesto |
| Escenario que cambia | Sólidos del mundo que se abren (el portal ya lo hace) | Muros que caen, losas hundidas, pilares que suben: sólidos que aparecen y desaparecen por orden del servidor |
| Toque de todos a la vez | Regla de los altares | Canalizar el toque y soltarse al recibir daño |
| Presentación y despedida | Cinemáticas compartidas por fases, con vídeo y respaldo del motor | Dos escenas nuevas |
| Modelo | Proceso de Blender por código | El coloso, con sus animaciones |
| Pruebas | Bots de servidor, flujo en navegador | Victoria con 1, 2 y 4; derrota y reintento por fase; nadie se salta fases |

**Riesgos que hay que medir antes:** el coloso y sus efectos en equipos sin tarjeta gráfica potente;
la memoria del servidor (512 MB compartidos); y que el patio de 12 m se queda justo para cinco
cuerpos, por eso la fase 2 sale a la explanada.

## Orden de trabajo propuesto

| Paso | Entrega | Se puede probar |
| --- | --- | --- |
| 1 | Modelo del coloso y sus animaciones | Hojas y capturas |
| 2 | Jefe en el servidor con la fase 1 completa | Bots: se llega a la fase 2 con 1, 2 y 4 jugadores |
| 3 | Escenario que cambia y fase 2 | Bots y navegador |
| 4 | Fase 3, derrota por fases y recompensa | Bots: victoria y reintento |
| 5 | Presentación en el cliente: modelo, avisos, barra, efectos | Flujo completo en navegador |
| 6 | Escenas con el motor (presentación y despedida) | Con cuatro navegadores |
| 7 | Vídeos de Kling de las dos escenas | Tras aprobar diseño y presupuesto |

## Cinemáticas

### «El despertar de Nojoch Tuunich» (presentación, compartida)

16 s en cuatro planos. Empieza cuando el grupo entra al patio.

| Plano | Duración | Qué pasa | Termina en |
| --- | --- | --- | --- |
| 1. La estatua | 4 s | El patio en silencio. Al fondo, lo que parecía una estatua cubierta de musgo y raíces. El cristal de jade late una vez. | Plano general del patio |
| 2. Las grietas | 4 s | Una grieta recorre el pecho de piedra; caen polvo y hojas; las raíces se rompen. | Primer plano del pecho |
| 3. Los glifos | 4 s | Los cuatro glifos intentan encenderse en jade… y se tiñen de magenta. Se abren los ojos. | Primer plano de la cabeza |
| 4. De pie | 4 s | El coloso se incorpora, el patio tiembla, alza un puño. | **La cámara de combate**, con él de pie en su sitio |

Subtítulo final: «Nojoch Tuunich ya no recuerda a quién guarda.»

### «El guardián recuerda» (despedida, compartida)

12 s en tres planos, al terminar la fase 3.

| Plano | Duración | Qué pasa |
| --- | --- | --- |
| 1 | 4 s | Las vetas magenta se apagan de la cabeza a los pies; los glifos del pecho se encienden en jade uno a uno. |
| 2 | 4 s | El coloso mira sus manos, las abre: entre ellas flota una pluma de jade. La acerca al grupo (visto desde arriba, sin mostrar caras). |
| 3 | 4 s | Vuelve a sentarse en su sitio, despierto. La pluma tiembla y gira sola hacia el oeste; lejos, el agua oscura del cenote devuelve un destello. |

Subtítulo final: «La pluma señala al cenote. Abajo hay alguien que también olvidó su nombre.»

### Presupuesto estimado de Kling (sin aprobar)

Con los precios ya medidos en «El sello cede»: 20 créditos por cuadro clave enriquecido y 8 por
segundo de vídeo a 1080p.

| | Despertar | El guardián recuerda |
| --- | --- | --- |
| Duración | 16 s | 12 s |
| Cuadros clave enriquecidos | 5 (100) | 4 (80) |
| Vídeo, una pasada | 128 | 96 |
| Total de una pasada | ~230 | ~180 |
| Con repeticiones (un coloso animado falla más que un escenario) | ~400 | ~300 |
| **Máximo propuesto** | **450** | **350** |

No se gasta nada hasta que apruebes el modelo, la mecánica y estos presupuestos.

## Recompensa y enlace con el Capítulo II

| | |
| --- | --- |
| Recompensa | **La Pluma de Jade**, primera pluma de Kukulkán. Persistente, una por jugador, como el Sello del Claro |
| Se nota en | El perfil del portal y una pluma en el tocado del alux |
| Qué abre | El guardián, despierto, se queda en el claro como personaje con quien hablar. El agua del cenote se aclara y aparece la escalera que baja: la entrada al Capítulo II, cerrada con un «Próximamente» hasta la Alpha 0.5 |
| Lo que cuenta | La pluma no es un trofeo: es una brújula. Señala a Áayin, el espíritu del cenote, que también olvidó su nombre |

Esto adelanta a la 0.3 la recompensa que la hoja de ruta ponía en la 0.4. La 0.4 queda para el
vínculo de Balam como desbloqueo narrativo y el pulido del capítulo.

## Decisiones que necesito

| Decisión | Opciones | Recomendación |
| --- | --- | --- |
| Barra de Silencio en vez de vida | Así · barra de vida clásica | Silencio: es lo que distingue a este jefe y encaja con «recordar, no destruir» |
| El combate sale del patio en la fase 2 | Sí · todo dentro del patio (habría que agrandarlo) | Salir: reutiliza la explanada y es el cambio de escenario más vistoso |
| Reintento por fases | Por fase · desde cero | Por fase: una derrota a los seis minutos no debe costar otros seis |
| Pluma de Jade en la 0.3 | Adelantarla · dejarla en la 0.4 | Adelantarla: sin recompensa el jefe no cierra nada |
