# ADR-001 · Decisiones Técnicas del Proyecto

**Proyecto:** Red Social de Formato Corto — Avance 2  
**Autor:** Henrique Alejandro Alvarado Castillo  
**Fecha:** 17 de septiembre de 2026  
**Estado:** Aceptado

---

## Contexto

Se requiere construir una red social minimalista con backend en Python, mínimo 2 contenedores, integración con AWS (S3 y RDS), e infraestructura como código. El proyecto debe incluir un pipeline de seguridad con evidencia de bloqueo y remediación.

---

## Decisiones tomadas

### 1. Framework: Flask sobre FastAPI

**Elegido:** Flask 3.0.3  
**Descartado:** FastAPI

**Por qué Flask:** Para un MVP de entrega individual con tiempo limitado, Flask requiere menos boilerplate. No se necesita validación de esquemas avanzada ni documentación automática de OpenAPI para este alcance. Flask es suficiente y más familiar para proyectos académicos en Python.

**Por qué no FastAPI:** FastAPI agrega valor en proyectos grandes con muchos endpoints y equipos. Para este MVP, el overhead de aprender Pydantic models no justifica el beneficio.

---

### 2. Base de datos: PostgreSQL sobre MySQL

**Elegido:** PostgreSQL 16 (RDS)  
**Descartado:** MySQL, SQLite

**Por qué PostgreSQL:** Soporte nativo de `TIMESTAMPTZ`, constraints de clave foránea robustos y mejor manejo de consultas complejas para el feed. AWS Academy soporta ambos, pero PostgreSQL es el estándar de la industria para nuevos proyectos.

**Por qué no SQLite:** No escala, no es compatible con RDS y no cumple el requisito de base de datos en AWS.

---

### 3. Caché: Redis sobre Memcached

**Elegido:** Redis 7.2.5 (contenedor)  
**Descartado:** Memcached, ElastiCache

**Por qué Redis:** Es la pieza técnica obligatoria del Tema 2. Se corre como contenedor propio en docker-compose, lo que demuestra la separación de servicios requerida. Redis también permite invalidación de claves específicas (cuando el usuario publica, se borra solo su clave de caché), algo que Memcached no hace de forma eficiente.

**Por qué no ElastiCache:** AWS Academy tiene restricciones. Usar Redis en contenedor es más directo y cumple igual el requisito.

---

### 4. Autenticación: JWT sobre sesiones de Flask

**Elegido:** JWT (PyJWT)  
**Descartado:** Flask-Session, Flask-Login

**Por qué JWT:** La API es stateless. Los tokens JWT permiten autenticación sin estado en el servidor, lo cual es compatible con múltiples contenedores o réplicas futuras. Además, el token se puede pasar en el header `Authorization`, estándar para APIs REST.

---

### 5. ORM: psycopg2 directo sobre SQLAlchemy

**Elegido:** psycopg2-binary  
**Descartado:** SQLAlchemy, Flask-SQLAlchemy

**Por qué psycopg2:** Para un MVP con pocas tablas y queries conocidos, usar el driver directo es más transparente y más fácil de auditar desde una perspectiva de seguridad (se ven exactamente las queries que se ejecutan). SQLAlchemy agrega abstracción que no se necesita aquí.

---

### 6. Infraestructura: Terraform sobre CloudFormation

**Elegido:** Terraform  
**Descartado:** CloudFormation, AWS CDK

**Por qué Terraform:** Es agnóstico al cloud, tiene mayor adopción en la industria y el curso ya lo menciona en la documentación oficial referenciada. Checkov, la herramienta de escaneo de IaC del pipeline, tiene reglas predefinidas para recursos de Terraform.

---

## Lo que se decidió NO cubrir

| Aspecto | Por qué se dejó fuera |
|---------|----------------------|
| HTTPS / TLS | En AWS Academy no se puede crear un certificado ACM sin dominio propio. El tráfico es HTTP en el laboratorio. |
| Rate limiting | Fuera del alcance del MVP. Se agregaría con Flask-Limiter en producción real. |
| Kubernetes | Opcional según las instrucciones. No se arriesga la entrega por el bono. |
| Tests automatizados | No son requisito de la entrega. |
| ElastiCache | Restricciones de AWS Academy. Redis en contenedor cumple el requisito. |
