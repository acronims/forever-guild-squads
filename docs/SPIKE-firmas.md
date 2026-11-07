# SPIKE: firmar registros con ed25519 en Lua puro

Fecha: 2026-11-07. Spike técnico, sin código de producción. Duración: unos 15 minutos.

## Veredicto

Es viable para **verificar** en el addon. Con 25 ms por verificación, 200 verificaciones seguidas suman unos 5 s, así que hay que repartirlas en varios frames o, mejor, firmar lotes y no registros sueltos. **Firmar** dentro del juego no se recomienda (ver Riesgos): el autor firma fuera, con node u openssl, y el addon solo verifica.

## Implementación elegida

**ccryptolib** de migeyel (https://github.com/migeyel/ccryptolib), módulo `ccryptolib/ed25519.lua` con `internal/{edwards25519,fq,fp,mp,sha512,packing,util}.lua`.
- Licencia **MIT** (© 2023 Miguel Oliveira): compatible con la MIT del addon. Basta con conservar el aviso de copyright.
- Está escrita para ComputerCraft (Lua 5.2 sin enteros de 64 bits). La aritmética de campo usa **doubles**, no enteros de 64 bits: encaja con Lua 5.1 y WoW.
- Para cargarla en Lua 5.1 o WoW hacen falta estos parches o shims, todos pequeños:
  1. `bit32` construido sobre la `bit` de WoW: band, bor, bxor, bnot, lshift, rshift, lrotate→`bit.rol`, extract. Hay que normalizar el resultado a sin signo con `% 2^32`.
  2. Dos literales `"\x80"` (sha512 y sha256): Lua 5.1 no tiene `\x`. Se cambian por `"\128"`.
  3. `load(string)` → `loadstring`. Lo usa `packing.lua`, que genera código; en WoW existe `loadstring`.
  4. `cc.expect`, `internal.hw` (periféricos de ComputerCraft) y `random` se sustituyen por stubs.
- Descartadas:
  - **philanc/plc** (MIT): solo trae `ec25519.lua` (X25519), sin ed25519, y además exige Lua 5.3 (enteros de 64 bits y `string.pack`).
  - lua-lockbox y luanacha: no revisadas por falta de tiempo. Hasta donde sé, lockbox no tiene ed25519; está sin verificar.

## Entorno de medida

- **Lua 5.1.5 nativo (PUC-Rio)**, sacado de los `.deb` de Debian (`lua5.1_5.1.5-9`) a /tmp sin root. `bit` = **LuaBitOp 1.0.2** (`lua-bitop`), la misma librería de la que viene la `bit` de WoW.
- CPU: Intel i7-8700B a 3.2 GHz (Mac mini, contenedor Linux). Un solo hilo.
- El código ajeno está en `/tmp/spike-ed/ccl/repo` y nunca se ejecutó ningún script suyo. El harness está en `/tmp/spike-ed-harness/bench.lua`, que carga los `.lua` como texto.
- Fengari (Lua 5.3 sobre node), el que usa `tests/sim`: **no medido**. El shim de `bit` para 5.3 falló y lo dejé por tiempo. La cifra útil es la de 5.1 nativo.

## Corrección (comprobado)

- Vector RFC 8032 §7.1 TEST 1: `publicKey(sk)` coincide con el valor esperado y `verify` acepta la firma oficial.
- Rechaza una firma con un byte alterado y rechaza un mensaje alterado.
- Interoperabilidad: el `crypto.verify` de node (OpenSSL) acepta una firma generada por ccryptolib sobre un registro de 200 B.

## Cifras (Lua 5.1.5 + LuaBitOp, mensaje de 200 B)

| Operación | Tiempo |
|---|---|
| derivar clave pública | 5.0 ms |
| 1 firma | 10.6 ms |
| 1 verificación | 25.2 ms |
| **200 verificaciones** | **5 042 ms** (las 200 válidas) |
| sha512 de 200 B (incluido en lo anterior) | 3.4 ms |

La firma sale más barata que la verificación porque usa la base fija G, que tiene tabla precalculada. La verificación multiplica además por la clave pública, que es una base variable.

## Tamaño en el canal

El addon serializa los strings como `s<len>:<bytes>` (`Core/Serialize.lua`). Después `S.escape` duplica los bytes `~ | \n \r \0`, es decir, 5 de los 256 valores posibles. Al final `Core/Chunk.lua` trocea en partes de 255 B con una cabecera `id:i/n:`.

| Campo | Crudo | Serializado | Tras escape (media) | Tras escape (peor caso) |
|---|---|---|---|---|
| firma | 64 B | 68 B | ~69.3 B | 132 B |
| clave pública | 32 B | 36 B | ~36.6 B | 68 B |
| juntas | 96 B | 104 B | ~106 B | 200 B |

- La clave del autor no debería viajar: va fija en el código del addon. Así, por registro solo viajan unos 69 B de firma, que caben en una parte de 255 B aunque restan espacio útil. Una firma por registro, en registros pequeños, aproximadamente duplica el número de partes, y la cola envía 1 parte por segundo.
- En hex serían 128 B, frente a los ~69 B del binario escapado. Conviene el binario, que la cadena ya admite.

## ¿Cabe en un frame de WoW?

- Un frame a 60 fps dura 16.7 ms. **Una sola verificación (25 ms) ya supera un frame**: es aceptable de forma puntual (un tirón de unos 25 ms), pero no en bucle.
- Hacer 200 seguidas son unos 5 s con el cliente congelado. Eso es inaceptable y además se acerca al corte de «script ran too long».
- Propuestas, de mejor a peor:
  1. **Firmar lotes, no registros.** El autor firma `sha512(lote canónico)` o un manifiesto con el hash de cada registro. Basta 1 verificación por lote (unos 25 ms) más un hash por registro. Es la opción recomendada.
  2. **Repartir en frames**: 1 verificación por `OnUpdate` o por tick de `C_Timer`, con cola. 200 firmas son unos 200 frames, de 3 a 5 s en segundo plano, a unos 25 ms por frame. Mejor pausarlo en combate (`InCombatLockdown`) y en encuentros, como ya hace la cola de `Comm`.
  3. Opciones no medidas: una tabla precalculada para la clave fija del autor, que convertiría `ed.mul(y, e)` en algo como `mulG` y podría ahorrar en torno a un tercio; usar `bit` directamente, sin el envoltorio `% 2^32`, para abaratar sha512.

## Riesgos

- **Firmar en el juego**: ccryptolib firma con un nonce **aleatorio**, no el determinista de RFC 8032, y WoW no ofrece un RNG criptográfico. Con nonces malos se puede filtrar la clave. Además, la clave privada no debe estar nunca en el addon. Solución: firmar fuera y que el addon solo verifique.
- Verificación no estricta: el propio autor de la librería avisa de que puede aceptar firmas adversariales que una implementación estricta rechazaría (maleabilidad). Si la firma se usa como identificador o para deduplicar, hay que canonizar antes.
- Las cifras son de un i7 de escritorio con PUC 5.1. La VM de WoW es otra (Lua 5.1 modificado) y los PCs de los jugadores varían: hay que medirlo en el cliente real con `debugprofilestop()` antes de decidir.
- Memoria y GC: la librería crea tablas en cada operación de campo. No he medido la presión de GC; con 200 verificaciones puede notarse.
- Portabilidad: los parches son pocos, pero son un fork local que hay que mantener (vendorizar ccryptolib con el aviso MIT).
- Fengari (simulador): no he validado que funcione allí. Es necesario si los tests del simulador cubren la verificación.
