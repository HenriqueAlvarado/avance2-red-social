# Evidencia de Promoción a Producción — Entrega Final del Reto

**Proyecto:** Red Social de Formato Corto — Tema 2
**Autor:** Henrique Alejandro Alvarado Castillo
**Fecha:** [COMPLETAR fecha del despliegue]

---

## Resumen del flujo De QA a Producción

1. El parche vulnerable se aplicó en **QA** (instancia del Avance 2).
2. El pipeline corrió en QA y **bloqueó el despliegue** (corrida roja) →
   evidencia en `reportes/pipeline_bloqueado.txt`.
3. Se **remedió** la inyección SQL (consulta parametrizada) y se actualizó PyJWT.
4. El pipeline volvió a correr en QA y pasó en **verde** →
   evidencia en `reportes/pipeline_verde.txt`.
5. El código **ya remediado y verde** se promovió a la instancia nueva de
   **Producción**. Nunca se aplicó el parche vulnerable directo en Producción.

---

## Datos de las instancias

| Instancia | Rol | IP / Endpoint | ID de instancia |
|-----------|-----|---------------|-----------------|
| QA (Avance 2) | Donde se aplicó el parche y se remedió | `98.89.46.152` | `i-04ce9e1b989583bde` |
| Producción (nueva) | Solo recibe código remediado y verde | [COMPLETAR IP de Producción] | [COMPLETAR ID] |

---

## Verificación de que la versión remediada corre en Producción

**Cómo se comprobó:** [COMPLETAR — por ejemplo, se abrió la app en la IP de
Producción y se probó el endpoint `/publicaciones/buscar?usuario=...`, que ahora
exige autenticación y no es inyectable.]

**Prueba de que el fix está activo en Producción:**
- El endpoint `/publicaciones/buscar` responde correctamente para búsquedas
  legítimas.
- Un payload de inyección (`' OR '1'='1`) ya **no** altera la consulta: devuelve
  vacío o error controlado, no todas las publicaciones.
- El endpoint exige token JWT (responde 401 sin autenticación).

**Capturas asociadas** (van en el Word de evidencias):
- Consola de AWS mostrando la instancia de Producción nueva.
- La aplicación remediada corriendo en la IP de Producción.

---

## Nota sobre el crédito de AWS Academy

Tener QA y Producción encendidas a la vez consume el doble de presupuesto. La
instancia de Producción se **terminó** en cuanto se tomó la evidencia, para no
gastar saldo de más.

> [COMPLETAR: confirma aquí que terminaste la instancia de Producción tras
> tomar las capturas, y la fecha.]
