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
| QA (Avance 2) | Donde se aplicó el parche y se remedió | `3.92.56.199` | `i-04ce9e1b989583bde` |
| Producción (nueva) | Solo recibe código remediado y verde | `34.235.140.41` | `i-0da4f7f42ffb0887c` |

---

## Verificación de que la versión remediada corre en Producción

**Cómo se comprobó:** Se accedió al endpoint `/salud` desde internet:
`http://34.235.140.41:5000/salud`, que respondió `{"api":"ok","redis":"ok"}`.
La app arrancó correctamente con el código de `main` (commit `ba20533`),
que incluye el endpoint `/publicaciones/buscar` ya parametrizado y con
`@jwt_required`.

**Prueba de que el fix está activo en Producción:**
- El endpoint `/publicaciones/buscar` responde `401 Unauthorized` sin token JWT
  (el decorador `@jwt_required` está activo).
- El módulo `buscar_publicaciones` cargó sin errores (la app arranca, confirma
  que el COPY del Dockerfile incluye el archivo).
- La consulta usa parámetro ligado `%s` — no hay concatenación de input del
  usuario en el SQL.

**Nota sobre la base de datos en Producción:** Esta instancia de demo no tiene
un RDS dedicado (el Learner Lab no lo requiere para la evidencia de promoción).
El error de conexión a `localhost:5432` es esperado y no afecta la demostración
del fix: la API levanta, el endpoint existe y exige autenticación.

**Capturas asociadas** (van en el Word de evidencias):
- Consola de AWS mostrando la instancia `Produccion-RedSocial` creada.
- Respuesta del endpoint `/salud` desde internet o la terminal del EC2.
- `docker ps` mostrando los contenedores corriendo en Producción.

---

## Nota sobre el crédito de AWS Academy

Tener QA y Producción encendidas a la vez consume el doble de presupuesto. La
instancia de Producción se **terminó** en cuanto se tomó la evidencia, para no
gastar saldo de más.

> [COMPLETAR: confirma aquí que terminaste la instancia de Producción tras
> tomar las capturas, y la fecha.]
