# Certificación cruzada de claves (Anexo G): investigación

8-nov 03:4x. Paso (1) del Anexo G. Estado: **no ejecutado** en código; cifras estimadas salvo donde se dice «medido».

## Tamaño
- Entrada = hash12(nombre‖clave) = 12 bytes → 16 caracteres en base64 (24 en hex).
- Certificado = `n` + entradas + firma (64 bytes → 88 base64) + cabecera ≈ 110 bytes.
- 200 claves oídas en persona: 200 × 16 + 110 ≈ **3,3 KB ≈ 14 partes** de 255 bytes (hex: ~5 KB, ~20 partes). Base64 obligatorio.
- S8 de 1 min: 20 clientes, cada uno oye en persona a 19 → 19 × 16 + 110 ≈ 420 bytes ≈ **2 partes** por certificado.

## Coste en S8 de 1 min (tope AF4: 5601)
- Medido sin certificados: claves 5009 partes (s8k1); con manifiestos, s8m1 en curso.
- Certificados por GUILD (no por destino): 20 emisores × (≈5 refirmas durante la ráfaga de logins con el debounce de 5 s + 1) × 2 partes ≈ **240 partes**.
- Por destino (como `m` en los D): 20 × 19 × 2 ≈ 760 partes por ronda → no cabe si los manifiestos ya se comen el margen. **Decisión de diseño: el certificado va en GUILD con el hello y cuando cambia n**, no en cada D.
- Si aun así se pasa: delta (solo altas y bajas desde el n anterior) o Bloom de 1 KB (k=7, 200 entradas → FP ≈ 0,0008 %; pero un FP certifica una clave falsa, así que el Bloom solo como último recurso).

## S11 y S15: cuántos verificados (cálculo exacto sobre el grafo de encuentros)
En S11 nunca hay más de 2 clientes a la vez y van en cadena: cada uno solo oye en persona a sus vecinos (Mb1↔Mb2↔Mb3↔Mb4↔Mb5). En S15 además el GM oye a todos.

| | S11 | S15 |
|---|---|---|
| Hoy (claves débiles, quórum 2 de reenviadores) | 26/50 (medido) | — |
| Certificados, ≥2 emisores fuertes | **26/50** | **38/50** |
| Certificados + 2.º salto a 0,5 | 26/50 | 38/50 |

Ejemplo: Mb1 solo oye en persona a Mb2. Todo lo que sabe de Mb4 le llega a través de Mb2, también el certificado de Mb3 (cuya clave tampoco ha oído). **Ninguna regla que pida 2 testigos independientes puede verificar a Mb4 en Mb1**: en una cadena solo hay un camino. Llegar a 50/50 exige confiar en un solo vecino, que es lo que AF2/AF6 prohíben (un alt conocido en persona falsificaría a cualquiera que no hayas visto).

**Conclusión: AF7 (50/50 y 10/10 en S11/S15) es incompatible con la regla de ≥2 certificados.** Decide BRO (ver PROGRESS 8-nov 03:4x).

## S16b (2 alts conocidos en persona)
- 2 alts que el honesto ha oído en persona certifican una clave falsa de Z → con la regla de ≥2, Z queda «certificada» con la clave falsa **si nadie honesto fuerte certifica la real**. Es el límite del diseño: 2 alts = quórum.
- Con 1 certificado honesto en contra → «disputada»: no aplica nada nuevo, sale en diag.
- Z en persona → gana su clave (BRO 03:09) y se descarta lo firmado con la falsa.
- Cuesta lo mismo que hoy con claves débiles de quórum 2, con una mejora: los alts tienen que haber estado online junto a la víctima (conocidos en persona), no basta con relayar.
