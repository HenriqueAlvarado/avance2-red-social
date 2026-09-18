# Red Social de Formato Corto — Avance 2

**Autor:** Henrique Alejandro Alvarado Castillo  
**Materia:** LSCA2314 · Herramientas de Tecnologías de Información  
**Periodo:** AD26 · Universidad Tecmilenio

---

## ¿Qué hace esta aplicación?

Una red social minimalista donde los usuarios pueden:

- Registrarse e iniciar sesión con JWT
- Publicar posts de máximo 280 caracteres
- Seguir y dejar de seguir a otros usuarios
- Dar y quitar likes a publicaciones
- Ver su feed personalizado (posts propios + de usuarios seguidos)
- Subir imágenes a S3
- Ver el perfil de cualquier usuario

**Pieza técnica distintiva (Tema 2):** El feed se sirve desde **Redis** (caché) para evitar consultas repetidas a la base de datos. Solo va a RDS cuando el caché está expirado o fue invalidado por una nueva publicación.

---

## Cómo levantar la aplicación

### Requisitos previos

- Docker y docker-compose instalados
- Credenciales de AWS configuradas
- RDS PostgreSQL creada y accesible desde la instancia

### Pasos

```bash
# 1. Clonar el repositorio
git clone <url-del-repo>
cd avance2-red-social

# 2. Crear el archivo .env basado en el ejemplo
cp .env.example .env
# Editar .env con tus valores reales

# 3. Levantar los contenedores
docker-compose up -d --build

# 4. Verificar que todo está corriendo
curl http://localhost:5000/salud
```

---

## Servicios de AWS utilizados

| Servicio | Propósito | Configuración |
|----------|-----------|---------------|
| **EC2** `t3.medium` | Instancia donde corre docker-compose | `i-04ce9e1b989583bde` |
| **RDS** PostgreSQL | Base de datos principal | Cifrada, sin acceso público |
| **S3** | Almacenamiento de imágenes de perfil y posts | Privado, cifrado AES256 |

---

## Arquitectura de contenedores

```
                    ┌─────────────────┐
   Internet ──────▶ │  API Flask      │ :5000
                    │  (Contenedor 1) │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
       ┌─────────────┐  ┌─────────┐  ┌──────────┐
       │  Redis      │  │  RDS    │  │   S3     │
       │ (Caché feed)│  │Postgres │  │  Media   │
       │(Contenedor2)│  │ AWS     │  │  AWS     │
       └─────────────┘  └─────────┘  └──────────┘
```

---

## Endpoints disponibles

| Método | Ruta | Descripción | Auth |
|--------|------|-------------|------|
| GET | `/salud` | Health check | No |
| POST | `/registro` | Crear cuenta | No |
| POST | `/login` | Iniciar sesión | No |
| GET | `/feed` | Feed personalizado (con caché Redis) | JWT |
| POST | `/publicaciones` | Crear publicación | JWT |
| DELETE | `/publicaciones/<id>` | Eliminar publicación | JWT |
| POST | `/seguir/<id>` | Seguir usuario | JWT |
| DELETE | `/seguir/<id>` | Dejar de seguir | JWT |
| POST | `/publicaciones/<id>/like` | Dar like | JWT |
| DELETE | `/publicaciones/<id>/like` | Quitar like | JWT |
| GET | `/perfil/<id>` | Ver perfil | JWT |
| POST | `/upload` | Subir imagen a S3 | JWT |

---

## Pipeline de seguridad

Ver `pipeline/pipeline.sh` y `docs/tabla_decisiones_pipeline.md`.
