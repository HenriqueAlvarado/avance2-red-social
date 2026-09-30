# Clasificación del Hallazgo — Entrega Final del Reto

**Proyecto:** Red Social de Formato Corto — Tema 2
**Autor:** Henrique Alejandro Alvarado Castillo
**Materia:** LSCA2314 · Herramientas de Tecnologías de Información
**Fecha:** 18 de septiembre de 2026
**Funcionalidad entregada con el parche:** Buscar publicaciones de un usuario por su nombre
**Archivo afectado:** `app/buscar_publicaciones.py`

---

## Resumen del hallazgo

El endpoint nuevo `GET /publicaciones/buscar?usuario=...` construye la consulta
SQL **concatenando directamente** el valor `usuario` que llega del cliente dentro
del texto de la consulta, sin usar parámetros ligados:

```python
nombre_usuario = request.args.get("usuario", "")

consulta = (
    "SELECT p.id, p.contenido, p.creado_en "
    "FROM publicaciones p JOIN usuarios u ON u.id = p.user_id "
    "WHERE u.username = '" + nombre_usuario + "' "
    "ORDER BY p.creado_en DESC LIMIT 20"
)
cur.execute(consulta)
```

El valor del cliente pasa a formar parte de la sentencia SQL como si fuera código,
no como dato. Eso permite que un atacante altere la estructura de la consulta.

---

## Clasificación

| Campo | Valor |
|-------|-------|
| **Tipo** | Inyección SQL (SQL Injection) |
| **Identificador** | CWE-89 — *Improper Neutralization of Special Elements used in an SQL Command* |
| **OWASP Top 10** | A03:2021 — Injection |
| **Reglas que lo detectan** | Semgrep `python.flask.security.injection.tainted-sql-string` y Bandit `B608` (*hardcoded_sql_expressions*) |
| **Severidad** | **Alta** (con potencial de Crítica según lo que se logre extraer) |
| **¿Falso positivo?** | No. Confirmado explotable (ver abajo). |

---

## Justificación de la severidad: **Alta**

Se evalúa por impacto y facilidad de explotación.

**Impacto (alto):**
- La consulta corre sobre la tabla `usuarios`, que contiene los hashes de
  contraseña (`password`), correos y datos de todos los usuarios.
- Con una inyección tipo `UNION SELECT` un atacante puede extraer esos datos
  aunque el endpoint solo "debería" devolver publicaciones.
- Se compromete la confidencialidad de toda la base, no solo de un registro.

**Facilidad de explotación (alta):**
- El endpoint es `GET` y **no requiere autenticación** (no lleva el decorador
  `@jwt_required`). Cualquiera con la URL puede llamarlo.
- El parámetro es un query string simple: se explota desde el navegador o con
  `curl`, sin herramientas especiales.

No se marca **Crítica** de forma absoluta porque la extracción masiva requiere
construir el `UNION` correcto (número y tipo de columnas), pero el salto de Alta
a Crítica es cuestión de minutos para un atacante con conocimiento básico. En un
sistema con datos reales de usuarios, tratar esto como Crítico es defendible.

---

## Prueba de explotabilidad (confirmación manual)

Payloads probados contra el endpoint:

1. **Evasión del filtro (devuelve todo):**
   ```
   GET /publicaciones/buscar?usuario=' OR '1'='1
   ```
   La cláusula `WHERE u.username = '' OR '1'='1'` es siempre verdadera, así que
   la consulta devuelve publicaciones de todos los usuarios, no del buscado.

2. **Exfiltración de credenciales (UNION):**
   ```
   GET /publicaciones/buscar?usuario=x' UNION SELECT username, password, creado_en FROM usuarios--
   ```
   Devuelve los hashes de contraseña y nombres de usuario en el campo donde el
   cliente espera ver publicaciones.

Ambos confirman que el input del cliente altera la estructura de la consulta.
**No es un falso positivo.**

---

## Nota sobre falsos positivos

Bandit `B608` a veces marca strings SQL que en realidad no reciben input del
usuario (por ejemplo, sentencias `CREATE TABLE` fijas). En este proyecto se
revisó cada hallazgo:

- El `init_db()` de `app.py` usa SQL **estático** (sin variables del cliente):
  **no es explotable**, sería un falso positivo si Bandit lo marcara.
- El resto de queries de `app.py` usan **parámetros ligados** (`%s`): correctas.
- El único hallazgo real y explotable es el de `buscar_publicaciones.py`.

Por eso la etapa del pipeline se enfoca en confirmar el patrón peligroso
(concatenación con dato del cliente), que es exactamente el caso de este parche.

---

## Cómo se comportó el pipeline ante este hallazgo (importante)

Al correr el pipeline **original** (el del Avance 2) sobre el parche vulnerable,
el resultado fue **ROJO (despliegue bloqueado)**, pero conviene ser preciso
sobre *qué* etapa lo detuvo, porque hubo un matiz:

1. **La Etapa 1 (Semgrep) SÍ detectó la inyección SQL.** El hallazgo real fue
   `python.flask.security.injection.tainted-sql-string` en
   `buscar_publicaciones.py`. Sin embargo, esa etapa estaba etiquetada como
   "Secrets Scanning" y mezclaba los configs `p/secrets` y `p/python`, así que
   **reportó el SQLi como si fuera un "secreto"**. El bloqueo fue correcto, pero
   el mensaje era engañoso.

2. **La Etapa 2 (Bandit) NO detuvo el SQLi.** Bandit sí lo *ve* (`B608`), pero lo
   clasifica como **MEDIUM**, y esa etapa solo bloquea en **HIGH/CRITICAL**. Es
   decir, el SAST dedicado a código Python dejaba pasar esta clase de falla.

3. **La Etapa 3 (Trivy) bloqueó por otra causa ajena al parche:** 6 CVEs
   HIGH/CRITICAL de la dependencia `PyJWT 2.13.0` (no relacionados con el SQLi).

**Conclusión honesta:** el pipeline detuvo el despliegue, pero la etapa pensada
para atrapar vulnerabilidades de código (Bandit) no habría frenado este SQLi por
sí sola, y la etapa que sí lo atrapó lo reportaba con el nombre equivocado. Por
eso, como parte de la Entrega Final, se **reorganizó el pipeline**:

- La **Etapa 1** quedó solo con reglas de secretos (`p/secrets`).
- Se agregó una **Etapa 2.5 dedicada a inyección** (Semgrep `p/python` + Bandit
  `B608`) que bloquea ante *cualquier* patrón de SQL construido con input del
  usuario y lo reporta con su nombre correcto (inyección SQL / CWE-89).

Esto cierra el hueco y deja el pipeline reportando el hallazgo de forma clara.
