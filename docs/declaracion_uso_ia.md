# Declaración de Uso de Inteligencia Artificial

**Proyecto:** Red Social de Formato Corto — Avance 2  
**Autor:** Henrique Alejandro Alvarado Castillo  
**Materia:** LSCA2314 · Herramientas de Tecnologías de Información  
**Fecha:** 17 de septiembre de 2026

---

## Herramientas de IA utilizadas

- **Kiro (Amazon)** — Asistente de desarrollo integrado en el IDE, usado como ingeniero DevSecOps y desarrollador senior de apoyo.

---

## Qué generó la IA

| Artefacto | Participación de la IA |
|-----------|------------------------|
| `app/app.py` | La IA generó la estructura base y los endpoints. Yo definí qué rutas necesitaba (feed, follows, likes) basándome en el tema elegido. |
| `app/Dockerfile` | La IA generó el Dockerfile endurecido con usuario no-root y HEALTHCHECK. |
| `docker-compose.yml` | La IA generó la orquestación de los dos contenedores. |
| `infra/main.tf` | La IA generó los recursos de Terraform. Yo revisé que S3 tuviera acceso público bloqueado y que RDS no fuera pública. |
| `pipeline/pipeline.sh` | La IA generó el script base. Yo definí qué herramientas usar y con qué umbrales, basándome en los riesgos de mi app. |
| Documentación (README, ADR, tabla) | La IA generó el primer borrador. Yo revisé y ajusté las justificaciones para que conectaran con los riesgos reales de mi aplicación. |

---

## Qué hice yo

- **Elegí el tema** (Red social, Tema 2) y la pieza técnica (Redis como caché de feed).
- **Tomé todas las decisiones de diseño:** qué framework usar (Flask vs FastAPI), qué ORM (psycopg2 directo), por qué JWT para autenticación.
- **Definí los umbrales del pipeline:** decidí que Semgrep bloquea con cualquier secreto porque no hay credenciales de baja criticidad; que Trivy y Bandit bloquean en HIGH/CRITICAL porque LOW no justifica frenar el despliegue en este contexto.
- **Revisé el código generado** para entender qué hace cada función antes de aceptarlo.
- **Configuré la infraestructura en AWS:** creé la instancia EC2, el security group, e instalé Docker en el servidor.
- **Corregiré los hallazgos del pipeline** cuando aparezcan en la corrida roja, porque entiendo qué causó cada error.

---

## Lo que no delegué en la IA

La justificación de cada decisión. Si el profesor me pregunta "¿por qué Bandit bloquea en HIGH y no en MEDIUM?", la respuesta viene de entender que un HIGH en código que maneja autenticación sí puede ser explotable, mientras que un MEDIUM frecuentemente es teórico o tiene mitigaciones compensatorias. Eso no es una respuesta de la IA — es una decisión que tomé yo.
