# Respuesta a Incidente — Entrega Final del Reto

**Proyecto:** Red Social de Formato Corto — Tema 2
**Autor:** Henrique Alejandro Alvarado Castillo
**Hallazgo:** Inyección SQL (CWE-89) en `GET /publicaciones/buscar`
**Fecha:** 18 de septiembre de 2026

Este documento separa deliberadamente las dos respuestas: la **contención
inmediata** (frenar el sangrado ahora) y la **prevención** (el arreglo real que
elimina la causa raíz y es lo que se promueve a Producción).

---

## 1. Contención inmediata

*Objetivo: reducir el riesgo AHORA MISMO, sin todavía corregir la causa raíz.*

**Acción tomada:** desactivar el endpoint nuevo mediante una bandera de
configuración, de forma que deje de responder mientras se prepara el fix.

Mecanismo concreto:
- Se introduce la variable de entorno `BUSCAR_HABILITADO` (por defecto `false`).
- Mientras esté en `false`, el endpoint responde `503 Service Unavailable` y no
  ejecuta ninguna consulta.
- Esto se puede activar/desactivar sin volver a desplegar el código, y frena el
  vector de ataque de inmediato.

Alternativas de contención válidas en un entorno real (documentadas como opción):
- Bloquear la ruta `/publicaciones/buscar` en el balanceador / WAF.
- Revertir el despliegue del parche en QA hasta tener el fix.

**Lo que la contención NO hace:** no corrige el código. Si se reactiva el
endpoint sin el fix, la vulnerabilidad vuelve. Por eso la contención es temporal
y siempre va seguida de la prevención.

---

## 2. Prevención (el arreglo real)

*Objetivo: eliminar la causa raíz para que esta clase de falla no vuelva a
ocurrir. Es lo que efectivamente se sube a Producción.*

**Causa raíz:** el valor del cliente se concatena dentro del texto SQL, así que
se interpreta como código.

**Arreglo:** usar **consultas parametrizadas** (parámetros ligados). El valor del
usuario deja de ser parte de la sentencia y pasa a ser un dato que el driver
escapa por nosotros. Se mantiene exactamente la misma funcionalidad (buscar
publicaciones por nombre de usuario), pero ya no es inyectable.

Antes (vulnerable):
```python
consulta = (
    "... WHERE u.username = '" + nombre_usuario + "' ..."
)
cur.execute(consulta)
```

Después (remediado):
```python
consulta = (
    "SELECT p.id, p.contenido, p.creado_en "
    "FROM publicaciones p JOIN usuarios u ON u.id = p.user_id "
    "WHERE u.username = %s "
    "ORDER BY p.creado_en DESC LIMIT 20"
)
cur.execute(consulta, (nombre_usuario,))
```

Medidas de refuerzo aplicadas junto al fix:
- **Validación de entrada:** si `usuario` viene vacío, se responde `400` sin
  tocar la base.
- **Protección del endpoint:** se agrega `@jwt_required` para que la búsqueda
  solo esté disponible a usuarios autenticados (defensa en profundidad).
- **Etapa en el pipeline:** se añadió la Etapa 2.5 (Semgrep `p/python` + Bandit
  `B608`) que bloquea el despliegue si vuelve a aparecer SQL construido por
  concatenación con input del usuario. Así, si en el futuro alguien reintroduce
  el patrón, el pipeline lo detiene antes de producción y lo reporta con su
  nombre correcto (inyección SQL / CWE-89), no como un "secreto".
- **Higiene de dependencias:** durante la corrida roja, Trivy detectó 6 CVEs
  HIGH/CRITICAL en `PyJWT 2.13.0` (ajenos al parche, pero presentes en la
  imagen). Se actualizó a `PyJWT 2.14.0`, que incluye los fixes de seguridad.
  Esto no es parte del SQLi, pero era necesario para dejar el pipeline en verde
  y forma parte de mantener el despliegue libre de vulnerabilidades conocidas.

---

## 3. Resumen contención vs prevención

| Aspecto | Contención inmediata | Prevención |
|---------|---------------------|------------|
| Qué hace | Apaga el endpoint (bandera / WAF) | Parametriza la consulta |
| Corrige la causa | No | Sí |
| Es temporal | Sí | No (es el estado final) |
| Va a Producción | No por sí sola | Sí, es lo que se promueve |
| Tiempo de aplicación | Segundos | El fix + su verificación en pipeline |
