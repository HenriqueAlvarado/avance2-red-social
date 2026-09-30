"""
Funcionalidad nueva (Entrega Final): buscar publicaciones por nombre de usuario.
Tema 2 — Red social de formato corto.

Producto pide: dentro del feed, un cuadro de búsqueda que permita encontrar
las publicaciones de un usuario específico por su nombre.

NOTA DE INTEGRACIÓN:
El parche original venía escrito para SQLAlchemy (from app.db import engine).
Este proyecto usa psycopg2 directo, así que se adaptó para reutilizar la misma
conexión get_db() de app.py.

REMEDIACIÓN (CWE-89 / SQL Injection):
La versión entregada del parche concatenaba el valor del cliente dentro del
texto SQL, lo que permitía inyección. Se corrigió usando consultas
parametrizadas (parámetros ligados con %s), se agregó validación de entrada y
se protegió el endpoint con JWT. La funcionalidad (buscar por usuario) se
mantiene idéntica.
"""
import os
from flask import Blueprint, request, jsonify

from app import jwt_required, get_db

buscar_bp = Blueprint("buscar", __name__)

# Bandera de contención: permite desactivar el endpoint sin redeploy.
BUSCAR_HABILITADO = os.environ.get("BUSCAR_HABILITADO", "true").lower() == "true"


@buscar_bp.route("/publicaciones/buscar", methods=["GET"])
@jwt_required
def buscar_por_usuario():
    """Devuelve las publicaciones de un usuario dado su nombre."""
    if not BUSCAR_HABILITADO:
        return jsonify({"error": "Búsqueda temporalmente deshabilitada"}), 503

    nombre_usuario = (request.args.get("usuario", "") or "").strip()
    if not nombre_usuario:
        return jsonify({"error": "El parámetro 'usuario' es obligatorio"}), 400

    # Consulta parametrizada: el valor viaja como dato ligado (%s), nunca como
    # parte del texto SQL. psycopg2 se encarga del escape, así que no hay forma
    # de alterar la estructura de la consulta desde el input del cliente.
    consulta = (
        "SELECT p.id, p.contenido, p.creado_en "
        "FROM publicaciones p JOIN usuarios u ON u.id = p.user_id "
        "WHERE u.username = %s "
        "ORDER BY p.creado_en DESC LIMIT 20"
    )

    conexion = get_db()
    cur = conexion.cursor()
    cur.execute(consulta, (nombre_usuario,))
    filas = cur.fetchall()
    cur.close()

    publicaciones = [
        {"id": f["id"], "contenido": f["contenido"], "creado_en": str(f["creado_en"])}
        for f in filas
    ]

    return jsonify({"usuario": nombre_usuario, "publicaciones": publicaciones})
