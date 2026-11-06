# RougeXHunter: traspaso de trabajo

Todo lo hecho y documentado hasta el 2026-11-06, y cómo seguir desde cualquier sitio. Tiene dos lectores: el dueño del proyecto, desde el móvil o en clase, y Claude, al empezar una sesión nueva sin contexto.

**Claude:** este archivo sustituye a la memoria local, que no existe en una sesión en la nube. Léelo entero antes de actuar. En la nube, si choca con las secciones 5, 6 o 7 de `CLAUDE.md`, manda este archivo.

## Para el dueño: cómo seguir desde clase
1. Abre [claude.ai/code](https://claude.ai/code).
2. Elige el entorno **Rouge X Hunter**. Ya es el predeterminado.
3. En el selector de repositorios añade **Rouge-X-Hunter-game-files** y **Rouge-X-Hunter-obsidian-vault**. Si no aparecen, instala la GitHub App de Claude en tu cuenta. Para empezar la web, añade también **Rouge-X-Hunter-WebApp**.
4. Escribe: `Lee HANDOFF.md, prepara la sesión y dime qué sigue`.

| En la nube se puede | En la nube no se puede |
|---|---|
| Leer y cambiar código en una rama | Probar el juego: no hay Roblox Studio |
| Documentar y subir el vault, si añadiste su repo | Usar Hermes y Gemini: tu `.env` no está allí, y no debe estar |
| Reconstruir el grafo de conocimiento | Usar Blender, Ollama u Obsidian |
| Empezar la web, cuando tú lo digas | Leer tu memoria local de Claude o los archivos de tu PC |

## Para Claude: al empezar una sesión
1. **Prepara la sesión.** Ejecuta esto. No sube nada a GitHub:
   ```bash
   bash scripts/cloud_bootstrap.sh --graph
   ```
   Deja el vault en `GameNotes/`, donde las herramientas lo esperan, e instala graphify, que `/session-log` necesita. Sin `--graph` tarda menos, si la sesión no va a tocar el vault. También avisa de ramas sin fusionar y notas pendientes. El paquete se llama `graphifyy`, con doble y: no es una errata.
2. **Si estás en `main`,** crea `claude/<fecha>-<tema>` antes de cambiar código. Al terminar, da el nombre de la rama.
3. **Si dice que falta el vault:** búscalo con `find / -name 00-Home.md -not -path '*/node_modules/*' 2>/dev/null`. Si no aparece, dile al dueño que añada `Rouge-X-Hunter-obsidian-vault` al abrir una sesión nueva. Hasta entonces tu documentación es este archivo, `CLAUDE.md`, `README.md` y `Game_concept.md`, que no es el GDD. El código sigue ahí, y manda si no coinciden.
4. **Si hay notas en `pending-vault-notes/`,** muévelas al vault y bórralas de `main` con `bash scripts/push_docs_to_main.sh --clear-pending "mensaje"`.
5. **Para preguntas de arquitectura,** lee `GameNotes/Graph/GRAPH_REPORT.md` antes de recorrer el código. Es mucho más barato.
6. **Documenta en cuanto haya un cambio o una decisión,** sin esperar al final, porque el dueño puede cerrar la sesión desde el móvil.
   - **Con vault:** usa `/session-log`. Si el vault no se puede subir, copia la nota como en el caso siguiente y dale el error al dueño. Un commit local del vault se pierde con la sesión.
   - **Sin vault:** no ejecutes `/session-log` ni `vault_session.js`. Escribe `pending-vault-notes/<fecha>-<tema>.md` con objetivo, archivos, decisiones, verificación, temas abiertos, notas del vault por actualizar y feedback.
7. **Si cambian las reglas, decisiones, bugs o siguientes pasos,** actualiza este archivo. Súbelo, junto con las notas pendientes, con:
   ```bash
   bash scripts/push_docs_to_main.sh "mensaje del commit"
   ```

## Reglas del dueño
- **La web está en pausa.** No la empieces hasta que el dueño lo pida expresamente en esa sesión. "Sigue con esto" nunca basta. Pregúntale.
- **El trabajo en el juego ya empezó.** El 2026-11-06 pidió arreglar cuanto antes el código contradictorio. Los arreglos siguen en una rama. Para funciones nuevas, "sigue con esto" solo basta si responde a una propuesta concreta tuya en esa misma sesión.
- **Feedback constante.** Pidió crítica honesta en cada sesión: "the more feedback the better". Añádela a `Feedback/Project-Feedback.md` y da lo más importante en tu último mensaje, sin suavizarla.
- **El GDD queda para casa.** Pidió hablar de él "once im home".
  - En la nube, supón que está en clase hasta que diga lo contrario.
  - Si pregunta por lo pendiente, di solo "queda un tema que pediste dejar para casa".
  - Cuando diga que está en casa, recuérdaselo enseguida.
  - Si aparece, pídele que lo suba o que abra una sesión en su PC. Va en `Reference/GDD.md` del vault. Compáralo con `Reference/GDD-Section-Map` y no cambies código por ello sin que lo pida.
- **El nombre es Rouge,** no Rogue. Su brief dice "Rogue X Hunter": corrígelo si reutilizas ese texto.
- **El juego va a dar dinero.** Cómo, todavía no está decidido.
- **Responde en el idioma de su último mensaje.** Escribe en español o en inglés.
- **Usa pocos agentes.** Como referencia, tres a la vez, salvo que él diga otra cosa. Un despliegue de 48 agentes agotó su límite de 5 horas. Agrupa el trabajo y guarda los resultados a medida que llegan.

## Reglas de trabajo
- Nunca subas `.env` ni claves. Nunca hagas force-push ni reescribas el historial.
- **Fusiona en `main` del juego solo con permiso expreso del dueño en esa sesión.** La nube no lo impide, así que depende de ti. La excepción son `HANDOFF.md` y `pending-vault-notes/`, que van directos a `main` con el script, porque si no la siguiente sesión leería una versión vieja. Si no está de acuerdo, quita esta excepción.
- **El vault se sube a su `main`,** con `npm run vault:publish`.
- **Web:** trabaja en la rama de la sesión, y sube a `main` solo con permiso. Sin vault no la empieces, porque el plan vive allí.
- **El pipeline de revisión no funciona en la nube.** La sección 5 de `CLAUDE.md` no se puede cumplir sin las claves. Todo cambio no trivial del juego se queda en una rama sin fusionar. Anótalo en la tabla de abajo, y di en tu último mensaje que no tuvo plan de Gemini ni revisión de Hermes.
- **Mientras un arreglo no esté fusionado,** la nota del vault dice "arreglado en la rama X, sin fusionar", y sus citas siguen apuntando a `main`.
- **`--!strict`:** no lo añadas a un archivo existente dentro de un arreglo, porque sin verificador no puedes comprobarlo. Los archivos nuevos sí lo llevan.
- **Routers:** si creas, cambias o mueves un archivo, actualiza a mano el router que corresponda en `memory/routers/`.
- **Commits:** termina con la línea de atribución que indique tu sesión.

### Ramas pendientes de revisión
Ninguna se fusiona hasta pasar el pipeline en su PC y probarla en Studio. El comando está en `.claude/skills/dual-debug/SKILL.md`. Si el pipeline tampoco funciona allí, decide el dueño.

| Rama | Qué cambia | Modo del pipeline | Probada en Studio |
|---|---|---|---|
| `claude/2026-11-05-fix-contradictions` | Bugs de personajes y datos, QTE juzgado por el servidor, `F` pulsada y mantenida, recuperación al caer | `dual-debug`, sin ejecutar: `claude` no está en el PATH | No. Tampoco verificada con un comprobador de tipos |

## Los tres repos
| Repo | Contiene | Estado |
|---|---|---|
| [Rouge-X-Hunter-game-files](https://github.com/jdanioliv/Rouge-X-Hunter-game-files) | Código del juego, Agentic OS, copia del pipeline de Blender | Activo, rama `main` |
| [Rouge-X-Hunter-obsidian-vault](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault) | Toda la documentación | Activo. En local vive en `GameNotes/`, que el repo del juego ignora |
| [Rouge-X-Hunter-WebApp](https://github.com/jdanioliv/Rouge-X-Hunter-WebApp) | La web | **En pausa.** Solo tiene un `README.md`, sin código |

Los tres parecen privados. **Fuera de los repos, a propósito:** `.env` con las claves, `node_modules/`, `output/` y `runs.log`. El dueño también guarda una copia en un pendrive, sin el trabajo posterior al 2026-11-05.

## Qué hemos hecho
**Primera sesión: conocer y documentar el proyecto**
- Leímos el vault y todo el código, y escribimos una nota por sistema con citas al código. Lectores independientes hicieron unas 47 correcciones.
- Auditamos el brief de la web contra el juego. De 49 afirmaciones, 29 eran correctas, 10 incorrectas y 10 describían sistemas que no existen. Otras 8 filas recogen cosas del juego que el brief omite.
- Escribimos el plan de la web y el roadmap, y creamos la rutina que documenta cada sesión.

**Segunda sesión: copia de seguridad y vault enlazado**
- Subimos el juego a GitHub por primera vez, incluido el Agentic OS, que nunca se había guardado, y el pipeline de Blender.
- Convertimos todos los enlaces del vault para que funcionen en Obsidian y en GitHub.
- Añadimos un grafo de conocimiento con graphify, que une el código y las notas sin gastar tokens de IA.
- Escribimos la arquitectura, el glosario, el mapa de repos, lo que se sabe del GDD, el análisis del builder de Deepwoken, un borrador del quiz y el registro de feedback.

**Tercera sesión: decisiones del dueño**
- Registramos el nombre, la decisión de ganar dinero y el GDD aplazado, con una nota sobre monetización.

**Cuarta sesión: seguir desde la nube**
- El dueño creó el entorno **Rouge X Hunter**. Añadimos este archivo, `scripts/cloud_bootstrap.sh` y `scripts/push_docs_to_main.sh`.

**Quinta sesión: arreglos del juego**
- El dueño pidió empezar con el código. Arreglamos en una rama sin fusionar los bugs conocidos y las reglas que el código incumplía, con sus decisiones sobre `F` y sobre caer. Un revisor independiente leyó el cambio. Nada se ha ejecutado en Studio.
- El dueño pidió abandonar la prueba en la nube.

**`main` sigue sin cambios en `src/`,** y la web sigue sin empezar.

## Mapa de la documentación
Rutas dentro del vault, en `GameNotes/` una vez preparada la sesión. Los enlaces abren en GitHub.

| Nota | Para qué |
|---|---|
| [00-Home](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/00-Home.md) | Punto de entrada |
| [Roadmap](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Roadmap.md) | Prioridades y los bugs principales |
| [Feedback/Project-Feedback](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Feedback/Project-Feedback.md) | Crítica honesta y preguntas abiertas |
| [Systems/Architecture-Overview](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Systems/Architecture-Overview.md) | Cómo encaja todo y cómo probar el juego |
| [Web-Hub/Web-Hub-Plan](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Web-Hub/Web-Hub-Plan.md) | Plan de la web por fases |
| [Web-Hub/Parity-Audit](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Web-Hub/Parity-Audit.md) | Brief contra código, fila por fila |
| [Web-Hub/Builder-Reference-Deepwoken](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Web-Hub/Builder-Reference-Deepwoken.md) | Qué hace ese builder y qué encaja aquí |
| [Web-Hub/Quiz-Design](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Web-Hub/Quiz-Design.md) | Borrador del quiz de Nen |
| [Web-Hub/Brief-2026-11-04](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Web-Hub/Brief-2026-11-04.md) | El brief original, sin cambios |
| [Reference/Monetization](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Reference/Monetization.md) | Qué cambia por ganar dinero |
| [Reference/GDD-Section-Map](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Reference/GDD-Section-Map.md) | Lo que el código revela del GDD perdido |
| [Reference/Glossary](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Reference/Glossary.md) | Cada término y qué hace en este juego |
| [Reference/Constants-Reference](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Reference/Constants-Reference.md) | Cada valor de ajuste |
| [Reference/Repositories](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Reference/Repositories.md) | Repos y lo que queda fuera de ellos |
| [Systems/Knowledge-Graph](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Systems/Knowledge-Graph.md) | Cómo consultar el grafo |
| [Process/Session-Documentation](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Process/Session-Documentation.md) | Cómo se documenta cada sesión |
| [Sessions/_Index](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/Sessions/_Index.md) | Historial de sesiones |

**Una nota por sistema, en `Systems/`:** Combat-System, Player-State-Service, Data-Persistence, Nen-Hexagon-and-Memory, Forced-Nen-Awakening, Meditation-and-Water-Divination, Seiyaku-Contracts-and-Hatsu, Client-Controllers, Network-Contract, Agentic-OS-Internals. `Systems/Nen-Combat-Core` es la intención de diseño, y difiere del código en seis mecánicas.

## Decisiones
| Decidido por el dueño | Fecha |
|---|---|
| Primero documentación, luego web, y más tarde cambios del juego | 2026-11-04 y 05 |
| El nombre es Rouge | 2026-11-05 |
| El juego va a dar dinero | 2026-11-05 |
| La web tiene repo propio, y está en pausa hasta nueva orden | 2026-11-05 |
| El builder debe sentirse como [deepwoken.co/builder](https://deepwoken.co/builder) | 2026-11-05 |
| Otros animes: se decidirá más adelante | 2026-11-04 |
| Empezar a arreglar el código del juego | 2026-11-06 |
| Pulsar `F` hace parry y mantenerla bloquea, como en Deepwoken | 2026-11-06 |
| Dos vidas al empezar. Al caer se regenera más rápido de lo normal, del 5% al 7-10% del total, hasta cierta cantidad | 2026-11-06 |
| Un jugador dormido pega menos que nadie (x0,7) | 2026-11-06 |
| Un Hatsu bloqueado o con parry no cuenta como fallo para `backfire` | 2026-11-06 |
| La ventana de parry se juzga en el juego, y se puede ajustar | 2026-11-06 |
| Fatal Overload quita una vida, no borra el personaje | 2026-11-06 |

**Preguntas abiertas para el dueño**
1. **Para cuando esté en casa:** ¿dónde está el GDD? Debería mirar en su pendrive.
2. ¿Cómo gana dinero el juego: solo cosméticos, o también poder? Recomiendo solo cosméticos.
3. ¿Se mantiene la identidad de Hunter x Hunter, o se usan nombres y mundo propios? Recomiendo nombres propios. No bloquea W0 ni W1, porque los nombres visibles irán en una sola tabla, pero hay que decidirlo antes de publicar la web o crear arte.
4. ¿Se ha jugado alguna vez el juego en Studio? No hay registro.
5. ¿`prototype_scale.rbxl`, en sus Documentos, tiene que ver con este juego?
6. ¿El builder es más importante de lo que asumí? Lo puse después del quiz y las sugerencias porque depende de un catálogo de habilidades que no existe.
7. ¿Dónde alojar la web?
8. ¿Cada cuánto cura el jugador caído, y con cuánta vida se levanta? Puse 8% cada 2 segundos y 30%, que son suposiciones mías.
9. ¿Debe existir regeneración normal, y solo fuera de combate? Hoy el código no tiene ninguna.

## Lo más importante que encontramos
- **El árbol de habilidades no afecta al juego.** Comprar un nodo gasta memoria y sube un contador que se guarda y la interfaz muestra, pero ninguna lógica de juego lo usa: `GetLearnedNodes` no tiene llamadas (`NenAffinityService.luau:123`). Tampoco hay habilidades con nombre. Es la mayor carencia de diseño, y bloquea el builder.
- **No consta que el juego se haya ejecutado.** El commit `fca5dd2` dice que meditación y adivinación no se probaron, y no hay registro de pruebas del resto. No hay tests, ni linter, ni `aftman.toml`. 19 de los 28 archivos Luau no tienen `--!strict`.
- **No hay mundo.** Ningún repo tiene un archivo de lugar. Para probar el despertar hay que etiquetar piezas a mano en Studio. La ruleta pide además poner `AUTO_AWAKEN_DEBUG` en `false` en local: con `true`, el NPC siempre responde `AlreadyAwakened` (`NenAwakeningService.luau:105-108`). No subas ese cambio, porque `CLAUDE.md` pide conservar el flag.
- **Falta el GDD.** Unos 40 comentarios del código lo citan.
- **La limpieza semanal nunca funcionó,** aunque el registro diga lo contrario. Sus tres informes solo contienen "Failed to spawn 'claude'".
- **La auditoría nocturna nunca ha revisado nada.** Solo mira archivos `.luau` cambiados en las últimas 24 horas (`nightly_code_audit.js:19-21`), y sus 40 ejecuciones registradas no encontraron ninguno.
- **Lo mejor del proyecto:** el presupuesto de Seiyaku, la arquitectura con el servidor como autoridad, y los dos caminos de despertar.

## Bugs conocidos
Encontrados leyendo el código, sin reproducirlos jugando. Los archivos están en `src/ServerScriptService/Services/`, y las líneas pueden moverse. **Los de esta lista están arreglados en `claude/2026-11-05-fix-contradictions`, sin fusionar ni probar. Las citas describen `main`.**

**Sigue abierto, también en la rama:**
- Resetear (Esc → Reset) estando caído parece evitar el Grip. Sin probar.
- Salir estando caído evita el Grip, porque el castigo por desconectarse en combate no existe aún.
- Los datos de depuración de Studio pueden llegar al almacén real.

**Ponen en riesgo personajes o datos:**
1. **Un desangrado borra un personaje de dos nodos.** `LoseSoulNode` no limpia `isDowned`, así que se repite en el siguiente Heartbeat (`PlayerStateService.luau:699-701`, `:520-545`).
2. **Rematar un cuerpo muerto quita más nodos.** La ruta de jugadores no comprueba `Health > 0` (`CombatService.luau:117`, `:152`).
3. **Un jugador expulsado borra el bloqueo de otro servidor,** lo que anula la protección contra duplicados (`DataPersistenceService.luau:198`, `:224-232`).
4. **Si falla el bloqueo, se juega y se guarda igual** (`DataPersistenceService.luau:68-73`).
5. **Salir durante la ruleta o el QTE esquiva el resultado** (`NenAwakeningService.luau:70-73`, `:180-183`).

**Reglas que no se cumplen:**
- El QTE de despertar se fía del cliente (`NenAwakeningService.luau:170`).
- Las compras de nodos esperan al autoguardado (`NenAffinityService.luau:142-156`).
- El sello de Ten falla si se agota el aura (`PlayerStateService.luau:690-696`).
- `NETWORK_TOLERANCE` no tiene efecto en el parry (`PlayerStateService.luau:143-150`, `:662-664`).

El Roadmap reúne los principales, con las dudas de equilibrio. Hay más en la sección "Observed in code" de cada nota de `Systems/`.

## Dinero: lo esencial
Detalle y fuentes en `Reference/Monetization.md`. Esto es consejo técnico, no legal.
- **Riesgo legal:** una reclamación DMCA válida retira el juego. Por suerte, solo un personaje aparece en texto visible: Kastro, en "the Kastro Trap" (`SkillTreeController.client.luau:213`). Los términos visibles son unas 60 líneas como mucho, así que renombrar ahora es barato.
- **No vendas poder.** Vender linajes con estadísticas contradice el juego basado en habilidad y la promesa de "zero pay-to-win" del brief. Mejor cosméticos, empezando por el color del aura.
- **No vendas el dinero del juego.** Si se pudiera comprar con Robux, la ruleta de despertar pasaría a ser un objeto aleatorio de pago, con las reglas de Roblox sobre probabilidades.
- **Falta la base:** no hay código de compras ni datos de cuenta que sobrevivan a un borrado.

## Qué sigue
Nada está en marcha. Esperamos la decisión del dueño.

**Lo siguiente es que el dueño pruebe la rama en Studio:** pulsar y mantener `F`, caer y levantarse, un Grip y el QTE de despertar. Después decide si se fusiona.

**Su orden:**
1. **Documentación.** La primera pasada quedó terminada el 2026-11-05, aunque puede pedir más.
2. **La web,** que llamó "the most important thing". Dijo: "when i get to class i will start with the webapp just for you to have a foundation to work off of", y también "wait till further instructed". Así que espera a que lo pida.
3. **Cambios del juego,** que dejó para "later" y empezó el 2026-11-06 por los arreglos. Quedan más lógica, modelos y animaciones, zonas de carga, interfaz y bucle de juego.

**Cuando toque el juego, recomiendo este orden:**
1. Probar en Studio los arreglos de la rama y fusionarlos.
2. Añadir verificador de tipos y linter. `aftman.toml` con Rojo ya está en la rama.
3. Crear una arena de prueba por script, para poder jugar con una copia limpia.
4. Diseñar el catálogo de habilidades con el dueño.

**Mi crítica a su orden:** una web antes de un juego jugable crea expectativas sobre cosas que no existen. Por eso recomiendo empezar por el quiz y las sugerencias, con etiquetas honestas. Díselo, y decide él.

**Si pide empezar la web:** añade el repo de la web y sigue `Web-Hub/Web-Hub-Plan.md`, fases W0 y W1:
- **W0:** un generador en el repo del juego que exporta los datos de Luau a un `constants.js`, con `--out <ruta>` para escribirlo en el repo de la web. Exige un cambio pequeño en `src/`: exponer `EFFICIENCY`, `SLOT_COST_TIERS` y `AFFINITY_WEIGHTS`, que son privados. Pide permiso y hazlo en una rama, o copia esas tablas a mano y dilo.
- **W1:** portada y códice en HTML, CSS y ES modules sin compilación, con etiquetas "In game" o "Planned".
- **Con estas condiciones:** las cifras salen del código, nunca del brief. Sin prometer "zero pay-to-win". Aviso de proyecto no oficial, sin arte oficial. Nombres visibles en una sola tabla, porque la identidad sigue sin decidir.

## Comandos
| Comando | Hace |
|---|---|
| `bash scripts/cloud_bootstrap.sh --graph` | Prepara una sesión en la nube |
| `bash scripts/push_docs_to_main.sh "mensaje"` | Sube este archivo y las notas pendientes a `main` |
| `node scripts/vault_session.js new --title "..." --summary "..."` | Crea la nota de sesión |
| `npm run vault:graph` | Reconstruye el grafo. Sin tokens |
| `npm run vault:lint` | Comprueba enlaces, y que cada cita apunte a un archivo y una línea que existan, no que diga lo que afirma la nota |
| `npm run vault:publish -- --message "..."` | Convierte enlaces, revisa, hace commit y sube el vault |

Fuera de Windows, en los comandos de `Systems/Knowledge-Graph` cambia `Scripts/graphify.exe` por `bin/graphify`.

## Cuidado con esto
- **Citas al código:** si una nota y el código no coinciden, manda el código. Corrige la nota en esa misma sesión.
- **Rojo:** la versión 7.7.0 está instalada en el PC del dueño mediante Aftman. En `main` se niega a ejecutarse, porque no hay `aftman.toml`. En la rama de arreglos funciona.
- **Sin probar en la nube:** el dueño pidió abandonar la prueba el 2026-11-06. Este archivo y los dos scripts solo se han probado con copias simuladas. No se sabe en qué carpeta arranca una sesión con varios repos, dónde clona el segundo, ni si un repo se puede añadir a una sesión ya abierta. **La primera sesión real debe anotar aquí la carpeta inicial, la ruta de cada repo, la rama inicial y si pudo subir al vault.** Si no ves este archivo, busca el repo del juego con `ls ..`.
- **En el PC del dueño:** `claude` no estaba en el PATH del shell de la sesión anterior, y la limpieza semanal falla por eso, así que el pipeline de revisión puede fallar también allí.
