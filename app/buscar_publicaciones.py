"""
Funcionalidad nueva (Entrega Final): buscar publicaciones por nombre de usuario.
Tema 2 — Red social de formato corto.

Producto pide: dentro del feed, un cuadro de búsqueda que permita encontrar
las publicaciones de un usuario específico por su nombre.

NOTA DE INTEGRACIÓN:
El parche original venía escrito para SQLAlchemy (from app.db import engine).
Este proyecto usa psycopg2 directo, así que se adaptó para reutilizar la misma
conexión get_db() de app.py, manteniendo la lógica de la funcionalidad tal como
se entregó.
"""
from flask import Blueprint, request, jsonify

buscar_bp = Blueprint("buscar", __name__)


def obtener_conexion():
    """Reutiliza la conexión psycopg2 por-request definida en app.py."""
    from app import get_db
    return get_db()


@buscar_bp.route("/publicaciones/buscar", methods=["GET"])
def buscar_por_usuario():
    """Devuelve las publicaciones de un usuario dado su nombre."""
    nombre_usuario = request.args.get("usuario", "")

    # Se arma la consulta concatenando directamente el valor recibido del cliente.
    consulta = (
        "SELECT p.id, p.contenido, p.creado_en "
        "FROM publicaciones p JOIN usuarios u ON u.id = p.user_id "
        "WHERE u.username = '" + nombre_usuario + "' "
        "ORDER BY p.creado_en DESC LIMIT 20"
    )

    conexion = obtener_conexion()
    cur = conexion.cursor()
    cur.execute(consulta)
    filas = cur.fetchall()
    cur.close()

    publicaciones = [
        {"id": f["id"], "contenido": f["contenido"], "creado_en": str(f["creado_en"])}
        for f in filas
    ]

    return jsonify({"usuario": nombre_usuario, "publicaciones": publicaciones})
