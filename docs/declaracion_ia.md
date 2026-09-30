# Declaración de Uso de Inteligencia Artificial — Entrega Final del Reto

**Proyecto:** Red Social de Formato Corto — Tema 2
**Autor:** Henrique Alejandro Alvarado Castillo
**Materia:** LSCA2314 · Herramientas de Tecnologías de Información
**Fecha:** 18 de septiembre de 2026

---

## Herramientas de IA utilizadas

- **Kiro (Amazon)** — Asistente de desarrollo integrado en el IDE, usado como
  apoyo para investigar la falla, adaptar el parche, ajustar el pipeline y
  redactar la documentación.

---

## Qué hizo la IA en esta entrega

| Actividad | Participación de la IA |
|-----------|------------------------|
| Analizar el parche | La IA leyó `buscar_publicaciones.py` e identificó el patrón de inyección SQL (concatenación de input del cliente en la query). |
| Adaptar el parche | El parche venía para SQLAlchemy; la IA lo adaptó a psycopg2 para integrarlo en mi app, manteniendo la falla para la corrida roja. |
| Ajustar el pipeline | La IA propuso reorganizar la Etapa 1 (solo secretos) y agregar la Etapa 2.5 (inyección SQL con nombre correcto), tras ver que Bandit no bloqueaba el SQLi por ser MEDIUM. |
| Remediar el código | La IA escribió la versión parametrizada (`%s`) con validación de entrada y `@jwt_required`. |
| Redactar documentación | La IA generó los borradores de `clasificacion_hallazgo.md` y `respuesta_incidente.md`. |

---

## Qué hice yo y qué entendí

- **Ejecuté el flujo real:** apliqué el parche en mi instancia de QA, corrí el
  pipeline, vi el bloqueo, remedié y promoví a Producción.
- **Entendí la falla:** la inyección SQL ocurre porque el valor del cliente se
  concatena en el texto de la consulta. Verifiqué manualmente que un payload
  como `' OR '1'='1` altera la consulta.
- **Entendí por qué mi pipeline no la atrapaba bien:** Bandit clasifica el SQLi
  como MEDIUM y mi umbral era HIGH; Semgrep sí lo detectó pero lo reportaba como
  "secreto". Por eso decidí reorganizar las etapas.
- **Tomé la decisión de actualizar PyJWT:** entendí que los 6 CVEs de Trivy eran
  de una dependencia vieja, no del parche, y que había que actualizarla para
  dejar el pipeline en verde.
- **Revisé todo el código generado** antes de aceptarlo, para poder explicar
  cada cambio si el profesor pregunta.

---

## Lo que no delegué en la IA

La decisión de cómo clasificar la severidad y cómo separar contención de
prevención. La IA me dio el borrador, pero la justificación de por qué es "Alta"
(impacto sobre la tabla `usuarios` + endpoint sin autenticación) es mi criterio,
basado en entender qué datos hay en mi base y qué tan fácil es explotar el
endpoint.
