# Tabla de Decisiones del Pipeline de Seguridad

**Proyecto:** Red Social de Formato Corto  
**Autor:** Henrique Alejandro Alvarado Castillo  
**Fecha:** 17 de septiembre de 2026

---

## Riesgos concretos de esta aplicación

Esta red social tiene los siguientes riesgos específicos que justifican cada etapa del pipeline:

1. **Credenciales expuestas:** La app necesita acceder a RDS, Redis y S3. Si una clave AWS o una contraseña de DB se quema en el código y se sube al repo, cualquiera con acceso puede vaciar la base de datos o el bucket.

2. **Vulnerabilidades en código Python:** Flask mal configurado puede exponer el modo debug en producción, o una query mal escrita puede permitir inyección SQL.

3. **CVEs en la imagen Docker:** Las librerías del sistema y las dependencias Python (psycopg2, boto3, etc.) pueden tener vulnerabilidades conocidas que un atacante aproveche una vez que el contenedor esté corriendo.

4. **Configuración insegura de infraestructura:** Un bucket S3 sin bloqueo de acceso público o una RDS accesible desde internet son los errores de configuración más comunes en AWS y los más costosos.

---

## Tabla de decisiones

| # | Etapa | Herramienta | Riesgo que cubre | Umbral de bloqueo | Por qué este umbral |
|---|-------|-------------|-----------------|-------------------|---------------------|
| 1 | Secrets scanning | Semgrep (`p/secrets`) | Credenciales quemadas en código: AWS keys, passwords de DB, tokens JWT hardcodeados | **Cualquier hallazgo** (0 tolerancia) | Una sola credencial expuesta compromete toda la infraestructura. No existe un "secreto de baja severidad". |
| 2 | SAST Python | Bandit (`-ll`) | Vulnerabilidades en código Python: debug activo, uso inseguro de subprocess, manejo incorrecto de crypto | **HIGH o CRITICAL** | Un LOW en Bandit frecuentemente es un falso positivo o un riesgo teórico. Un HIGH en una app que maneja autenticación y datos de usuarios sí justifica frenar el despliegue. |
| 3 | Vulnerabilidades en imagen | Trivy | CVEs en librerías del sistema y dependencias Python dentro del contenedor | **HIGH o CRITICAL** | Un CVE CRITICAL en la imagen puede ser explotable remotamente. HIGH también, si el contenedor está expuesto. Un MEDIUM o LOW no justifica bloquear porque tiene mitigaciones compensatorias o no es explotable en este contexto. |
| 4 | IaC scanning | Checkov | Configuraciones inseguras en Terraform: S3 sin cifrado, RDS pública, SGs permisivos | **Checks fallidos en recursos críticos** | Los recursos de esta app (S3 y RDS) manejan datos de usuarios. Un misconfiguration aquí tiene impacto directo en privacidad y disponibilidad. |
| 5 | SBOM | Syft (CycloneDX) | Inventario de dependencias para rastrear componentes comprometidos en el futuro | **No bloquea** (genera artefacto) | El SBOM por sí solo no indica un riesgo actual, pero es indispensable para responder rápido si mañana se descubre un CVE en una librería que usamos. Sin SBOM, no sabríamos si estamos afectados. |

---

## Qué se decidió NO cubrir y por qué

| Control | Por qué se dejó fuera |
|---------|----------------------|
| DAST (escaneo dinámico) | Requiere la app corriendo con datos reales. Viable en un pipeline de staging, pero fuera del alcance de este MVP. |
| Escaneo de dependencias Python separado (pip-audit) | Trivy ya cubre las dependencias Python al escanear la imagen completa. Agregar pip-audit sería redundante. |
| Firmado de imagen (cosign) | Añade complejidad de gestión de claves que no se justifica para un entorno de laboratorio académico. |
| Análisis de licencias | No hay restricciones de licenciamiento en este proyecto académico. |

---

## Lógica de decisión final

El pipeline termina en un único veredicto:

- Si **todas** las etapas pasan sus umbrales → `exit 0` → **VERDE / PERMITIR**
- Si **cualquier** etapa supera su umbral → `exit 1` → **ROJO / BLOQUEAR**

Este diseño sigue el principio de _fail-fast_: cualquier hallazgo crítico detiene el pipeline inmediatamente y no permite el despliegue hasta que se remedie.
