"""
Red Social de Formato Corto - API principal
Backend: Flask + PostgreSQL (RDS) + Redis (caché de feed) + S3 (media)
"""

import os
import json
import boto3
import redis
import psycopg2
import psycopg2.extras
from functools import wraps
from datetime import datetime, timedelta, timezone

from flask import Flask, request, jsonify, g, render_template
from werkzeug.security import generate_password_hash, check_password_hash
import jwt

app = Flask(__name__)

# ── Configuración desde variables de entorno ────────────────────────────────
app.config["SECRET_KEY"] = os.environ["SECRET_KEY"]

DB_HOST     = os.environ["DB_HOST"]
DB_PORT     = os.environ.get("DB_PORT", "5432")
DB_NAME     = os.environ["DB_NAME"]
DB_USER     = os.environ["DB_USER"]
DB_PASSWORD = os.environ["DB_PASSWORD"]

REDIS_HOST  = os.environ.get("REDIS_HOST", "redis")
REDIS_PORT  = int(os.environ.get("REDIS_PORT", 6379))

S3_BUCKET   = os.environ["S3_BUCKET"]
AWS_REGION  = os.environ.get("AWS_REGION", "us-east-1")

FEED_CACHE_TTL = int(os.environ.get("FEED_CACHE_TTL", 60))  # segundos

# ── Clientes externos ────────────────────────────────────────────────────────
def get_db():
    if "db" not in g:
        g.db = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            cursor_factory=psycopg2.extras.RealDictCursor,
        )
    return g.db


def get_redis():
    if "redis" not in g:
        g.redis = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
    return g.redis


def get_s3():
    return boto3.client("s3", region_name=AWS_REGION)


@app.teardown_appcontext
def close_db(exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()


# ── Inicialización de la BD ──────────────────────────────────────────────────
def init_db():
    db = get_db()
    cur = db.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS usuarios (
            id          SERIAL PRIMARY KEY,
            username    VARCHAR(50)  UNIQUE NOT NULL,
            email       VARCHAR(120) UNIQUE NOT NULL,
            password    VARCHAR(256) NOT NULL,
            bio         TEXT         DEFAULT '',
            avatar_url  TEXT         DEFAULT '',
            creado_en   TIMESTAMPTZ  DEFAULT NOW()
        );

        CREATE TABLE IF NOT EXISTS publicaciones (
            id          SERIAL PRIMARY KEY,
            user_id     INTEGER REFERENCES usuarios(id) ON DELETE CASCADE,
            contenido   VARCHAR(280) NOT NULL,
            imagen_url  TEXT         DEFAULT '',
            creado_en   TIMESTAMPTZ  DEFAULT NOW()
        );

        CREATE TABLE IF NOT EXISTS follows (
            seguidor_id  INTEGER REFERENCES usuarios(id) ON DELETE CASCADE,
            seguido_id   INTEGER REFERENCES usuarios(id) ON DELETE CASCADE,
            creado_en    TIMESTAMPTZ DEFAULT NOW(),
            PRIMARY KEY (seguidor_id, seguido_id)
        );

        CREATE TABLE IF NOT EXISTS likes (
            user_id  INTEGER REFERENCES usuarios(id) ON DELETE CASCADE,
            post_id  INTEGER REFERENCES publicaciones(id) ON DELETE CASCADE,
            PRIMARY KEY (user_id, post_id)
        );
    """)
    db.commit()
    cur.close()


# ── Decorador JWT ────────────────────────────────────────────────────────────
def jwt_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return jsonify({"error": "Token requerido"}), 401
        token = auth.split(" ", 1)[1]
        try:
            payload = jwt.decode(token, app.config["SECRET_KEY"], algorithms=["HS256"])
            g.user_id = payload["sub"]
        except jwt.ExpiredSignatureError:
            return jsonify({"error": "Token expirado"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"error": "Token inválido"}), 401
        return f(*args, **kwargs)
    return decorated


# ── /salud ───────────────────────────────────────────────────────────────────
@app.route("/")
def index():
    return render_template("index.html")


@app.route("/salud")
def salud():
    estado = {"api": "ok", "redis": "ok", "db": "ok"}
    try:
        r = get_redis()
        r.ping()
    except Exception as e:
        estado["redis"] = f"error: {e}"

    try:
        db = get_db()
        cur = db.cursor()
        cur.execute("SELECT 1")
        cur.close()
    except Exception as e:
        estado["db"] = f"error: {e}"

    http_code = 200 if all(v == "ok" for v in estado.values()) else 503
    return jsonify(estado), http_code


# ── Autenticación ────────────────────────────────────────────────────────────
@app.route("/registro", methods=["POST"])
def registro():
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    email    = (data.get("email") or "").strip()
    password = data.get("password") or ""

    if not username or not email or not password:
        return jsonify({"error": "username, email y password son obligatorios"}), 400
    if len(password) < 6:
        return jsonify({"error": "La contraseña debe tener al menos 6 caracteres"}), 400

    hashed = generate_password_hash(password)
    try:
        db = get_db()
        cur = db.cursor()
        cur.execute(
            "INSERT INTO usuarios (username, email, password) VALUES (%s, %s, %s) RETURNING id",
            (username, email, hashed),
        )
        user_id = cur.fetchone()["id"]
        db.commit()
        cur.close()
    except psycopg2.errors.UniqueViolation:
        return jsonify({"error": "username o email ya existe"}), 409

    token = _generar_token(user_id)
    return jsonify({"token": token, "user_id": user_id}), 201


@app.route("/login", methods=["POST"])
def login():
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""

    if not username or not password:
        return jsonify({"error": "username y password son obligatorios"}), 400

    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT id, password FROM usuarios WHERE username = %s", (username,))
    row = cur.fetchone()
    cur.close()

    if not row or not check_password_hash(row["password"], password):
        return jsonify({"error": "Credenciales inválidas"}), 401

    token = _generar_token(row["id"])
    return jsonify({"token": token, "user_id": row["id"]}), 200


def _generar_token(user_id):
    payload = {
        "sub": user_id,
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc) + timedelta(hours=24),
    }
    return jwt.encode(payload, app.config["SECRET_KEY"], algorithm="HS256")


# ── Publicaciones ────────────────────────────────────────────────────────────
@app.route("/publicaciones", methods=["POST"])
@jwt_required
def crear_publicacion():
    data = request.get_json(silent=True) or {}
    contenido = (data.get("contenido") or "").strip()
    if not contenido:
        return jsonify({"error": "contenido es obligatorio"}), 400
    if len(contenido) > 280:
        return jsonify({"error": "máximo 280 caracteres"}), 400

    db = get_db()
    cur = db.cursor()
    cur.execute(
        "INSERT INTO publicaciones (user_id, contenido) VALUES (%s, %s) RETURNING id, creado_en",
        (g.user_id, contenido),
    )
    row = cur.fetchone()
    db.commit()
    cur.close()

    # Invalida caché del feed del autor y sus seguidores
    _invalidar_cache_feed(g.user_id)

    return jsonify({"id": row["id"], "creado_en": str(row["creado_en"])}), 201


@app.route("/publicaciones/<int:post_id>", methods=["DELETE"])
@jwt_required
def eliminar_publicacion(post_id):
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "DELETE FROM publicaciones WHERE id = %s AND user_id = %s RETURNING id",
        (post_id, g.user_id),
    )
    deleted = cur.fetchone()
    db.commit()
    cur.close()
    if not deleted:
        return jsonify({"error": "No encontrado o no autorizado"}), 404
    _invalidar_cache_feed(g.user_id)
    return jsonify({"mensaje": "eliminado"}), 200


# ── Feed con caché Redis ─────────────────────────────────────────────────────
@app.route("/feed")
@jwt_required
def feed():
    r = get_redis()
    cache_key = f"feed:{g.user_id}"

    cached = r.get(cache_key)
    if cached:
        posts = json.loads(cached)
        return jsonify({"fuente": "cache", "posts": posts}), 200

    db = get_db()
    cur = db.cursor()
    cur.execute("""
        SELECT p.id, p.contenido, p.imagen_url, p.creado_en,
               u.username, u.avatar_url,
               (SELECT COUNT(*) FROM likes l WHERE l.post_id = p.id) AS likes
        FROM publicaciones p
        JOIN usuarios u ON u.id = p.user_id
        WHERE p.user_id = %s
           OR p.user_id IN (
               SELECT seguido_id FROM follows WHERE seguidor_id = %s
           )
        ORDER BY p.creado_en DESC
        LIMIT 50
    """, (g.user_id, g.user_id))
    rows = cur.fetchall()
    cur.close()

    posts = []
    for row in rows:
        posts.append({
            "id":         row["id"],
            "contenido":  row["contenido"],
            "imagen_url": row["imagen_url"],
            "creado_en":  str(row["creado_en"]),
            "username":   row["username"],
            "avatar_url": row["avatar_url"],
            "likes":      row["likes"],
        })

    r.setex(cache_key, FEED_CACHE_TTL, json.dumps(posts))
    return jsonify({"fuente": "db", "posts": posts}), 200


def _invalidar_cache_feed(user_id):
    try:
        r = get_redis()
        r.delete(f"feed:{user_id}")
        # También invalida el feed de los seguidores del autor
        db = get_db()
        cur = db.cursor()
        cur.execute("SELECT seguidor_id FROM follows WHERE seguido_id = %s", (user_id,))
        for row in cur.fetchall():
            r.delete(f"feed:{row['seguidor_id']}")
        cur.close()
    except Exception:
        pass  # No bloquear si Redis falla


# ── Follows ──────────────────────────────────────────────────────────────────
@app.route("/seguir/<int:user_id>", methods=["POST"])
@jwt_required
def seguir(user_id):
    if user_id == g.user_id:
        return jsonify({"error": "No puedes seguirte a ti mismo"}), 400
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(
            "INSERT INTO follows (seguidor_id, seguido_id) VALUES (%s, %s)",
            (g.user_id, user_id),
        )
        db.commit()
    except psycopg2.errors.UniqueViolation:
        return jsonify({"error": "Ya sigues a este usuario"}), 409
    finally:
        cur.close()
    _invalidar_cache_feed(g.user_id)
    return jsonify({"mensaje": f"Ahora sigues al usuario {user_id}"}), 201


@app.route("/seguir/<int:user_id>", methods=["DELETE"])
@jwt_required
def dejar_seguir(user_id):
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "DELETE FROM follows WHERE seguidor_id = %s AND seguido_id = %s RETURNING seguidor_id",
        (g.user_id, user_id),
    )
    deleted = cur.fetchone()
    db.commit()
    cur.close()
    if not deleted:
        return jsonify({"error": "No seguías a este usuario"}), 404
    _invalidar_cache_feed(g.user_id)
    return jsonify({"mensaje": "Dejaste de seguir"}), 200


# ── Likes ────────────────────────────────────────────────────────────────────
@app.route("/publicaciones/<int:post_id>/like", methods=["POST"])
@jwt_required
def dar_like(post_id):
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(
            "INSERT INTO likes (user_id, post_id) VALUES (%s, %s)",
            (g.user_id, post_id),
        )
        db.commit()
    except psycopg2.errors.UniqueViolation:
        return jsonify({"error": "Ya diste like"}), 409
    finally:
        cur.close()
    return jsonify({"mensaje": "Like registrado"}), 201


@app.route("/publicaciones/<int:post_id>/like", methods=["DELETE"])
@jwt_required
def quitar_like(post_id):
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "DELETE FROM likes WHERE user_id = %s AND post_id = %s RETURNING user_id",
        (g.user_id, post_id),
    )
    deleted = cur.fetchone()
    db.commit()
    cur.close()
    if not deleted:
        return jsonify({"error": "No habías dado like"}), 404
    return jsonify({"mensaje": "Like eliminado"}), 200


# ── Perfil ───────────────────────────────────────────────────────────────────
@app.route("/perfil/<int:user_id>")
@jwt_required
def perfil(user_id):
    db = get_db()
    cur = db.cursor()
    cur.execute("""
        SELECT u.id, u.username, u.bio, u.avatar_url, u.creado_en,
               (SELECT COUNT(*) FROM follows WHERE seguido_id   = u.id) AS seguidores,
               (SELECT COUNT(*) FROM follows WHERE seguidor_id  = u.id) AS siguiendo,
               (SELECT COUNT(*) FROM publicaciones WHERE user_id = u.id) AS posts
        FROM usuarios u WHERE u.id = %s
    """, (user_id,))
    row = cur.fetchone()
    cur.close()
    if not row:
        return jsonify({"error": "Usuario no encontrado"}), 404
    row["creado_en"] = str(row["creado_en"])
    return jsonify(dict(row)), 200


# ── Upload de imagen a S3 ────────────────────────────────────────────────────
@app.route("/upload", methods=["POST"])
@jwt_required
def upload_imagen():
    if "file" not in request.files:
        return jsonify({"error": "No se envió archivo"}), 400
    file = request.files["file"]
    if file.filename == "":
        return jsonify({"error": "Nombre de archivo vacío"}), 400

    ext = file.filename.rsplit(".", 1)[-1].lower()
    if ext not in {"jpg", "jpeg", "png", "gif", "webp"}:
        return jsonify({"error": "Tipo de archivo no permitido"}), 400

    key = f"media/{g.user_id}/{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S%f')}.{ext}"
    s3 = get_s3()
    s3.upload_fileobj(
        file,
        S3_BUCKET,
        key,
        ExtraArgs={"ContentType": file.content_type},
    )
    url = f"https://{S3_BUCKET}.s3.{AWS_REGION}.amazonaws.com/{key}"
    return jsonify({"url": url}), 201


# ── Arranque ─────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    with app.app_context():
        init_db()
    app.run(host="0.0.0.0", debug=False)
