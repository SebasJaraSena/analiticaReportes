"""Moodle SSO via Web Services token authentication.

Flow:
  1. POST login/token.php → get wstoken (validates credentials against Moodle)
  2. Look up user info from Moodle DB using the token (no WS function needed)
"""
from __future__ import annotations

import logging

import httpx
import psycopg2

from api.config import settings

logger = logging.getLogger(__name__)


def _moodle_headers() -> dict:
    if settings.moodle_host_header:
        return {"Host": settings.moodle_host_header}
    return {}


def _moodle_conn():
    dsn = (
        f"host={settings.moodle_db_host} port={settings.moodle_db_port} "
        f"dbname={settings.moodle_db_name} user={settings.moodle_db_user} "
        f"password={settings.moodle_db_password}"
    )
    return psycopg2.connect(dsn)


def get_moodle_token(username: str, password: str) -> str:
    """Authenticate against Moodle, return wstoken."""
    try:
        resp = httpx.post(
            f"{settings.moodle_url}/login/token.php",
            headers=_moodle_headers(),
            data={
                "username": username,
                "password": password,
                "service": settings.moodle_ws_service,
            },
            timeout=10,
        )
        resp.raise_for_status()
    except httpx.HTTPError as exc:
        logger.error("Moodle token request failed: %s", exc)
        raise ConnectionError("No se pudo conectar con Moodle.")

    data = resp.json()
    if "error" in data:
        raise ValueError(data.get("error", "Credenciales inválidas."))
    return data["token"]


def get_moodle_user_info(wstoken: str) -> dict:
    """Look up user info from Moodle DB using the issued wstoken.

    No web service function required — token is stored in mdl_external_tokens
    after login/token.php succeeds.
    """
    sql = """
        SELECT mu.id, mu.username, mu.email,
               mu.firstname || ' ' || mu.lastname AS fullname
        FROM public.mdl_external_tokens met
        JOIN public.mdl_user mu ON mu.id = met.userid
        WHERE met.token = %s
          AND (met.validuntil = 0 OR met.validuntil > EXTRACT(EPOCH FROM NOW())::int)
          AND mu.deleted = 0
          AND mu.suspended = 0
    """
    try:
        conn = _moodle_conn()
        with conn.cursor() as cur:
            cur.execute(sql, (wstoken,))
            row = cur.fetchone()
        conn.close()
    except Exception as exc:
        logger.error("Moodle DB lookup failed: %s", exc)
        raise ConnectionError("No se pudo verificar el token en la base de datos de Moodle.")

    if row is None:
        raise ValueError("Token inválido o expirado.")

    userid, username, email, fullname = row
    if not email:
        raise ValueError("El usuario de Moodle no tiene email configurado.")

    return {
        "userid": userid,
        "username": username,
        "email": email,
        "fullname": fullname,
    }


def get_moodle_user_info_by_token(wstoken: str) -> dict:
    """Same as get_moodle_user_info but accepts token string directly (for autologin endpoint)."""
    return get_moodle_user_info(wstoken)


def revoke_moodle_token(email: str) -> None:
    """Delete Moodle wstoken for the given user email from mdl_external_tokens."""
    sql_userid = "SELECT id FROM public.mdl_user WHERE email = %s AND deleted = 0"
    sql_delete = """
        DELETE FROM public.mdl_external_tokens
        WHERE userid = %s
          AND externalserviceid = (
              SELECT id FROM public.mdl_external_services WHERE shortname = %s
          )
    """
    try:
        conn = _moodle_conn()
        with conn.cursor() as cur:
            cur.execute(sql_userid, (email,))
            row = cur.fetchone()
            if row:
                cur.execute(sql_delete, (row[0], settings.moodle_ws_service))
        conn.commit()
        conn.close()
    except Exception as exc:
        logger.warning("Could not revoke Moodle token for %s: %s", email, exc)


def get_user_moodle_roles(userid: int) -> set[str]:
    """Return set of system-level role shortnames assigned to the user."""
    sql = """
        SELECT r.shortname
        FROM public.mdl_role_assignments ra
        JOIN public.mdl_role r ON r.id = ra.roleid
        JOIN public.mdl_context ctx ON ctx.id = ra.contextid
        WHERE ra.userid = %s AND ctx.contextlevel = 10
    """
    try:
        conn = _moodle_conn()
        with conn.cursor() as cur:
            cur.execute(sql, (userid,))
            rows = cur.fetchall()
        conn.close()
        return {row[0] for row in rows}
    except Exception as exc:
        logger.warning("Could not fetch Moodle roles for userid %s: %s", userid, exc)
        return set()


def is_moodle_siteadmin(userid: int) -> bool:
    """Check if user is in Moodle's siteadmins list."""
    try:
        conn = _moodle_conn()
        with conn.cursor() as cur:
            cur.execute("SELECT value FROM public.mdl_config WHERE name = 'siteadmins'")
            row = cur.fetchone()
        conn.close()
        if not row:
            return False
        admin_ids = {s.strip() for s in row[0].split(",")}
        return str(userid) in admin_ids
    except Exception as exc:
        logger.warning("Could not check siteadmins: %s", exc)
        return False


def check_user_access(userid: int) -> tuple[bool, bool]:
    """Return (has_access, is_admin) based on Moodle roles.

    is_admin=True when user is siteadmin or has 'manager' role.
    """
    if is_moodle_siteadmin(userid):
        return True, True

    roles = get_user_moodle_roles(userid)
    allowed = settings.moodle_allowed_roles_set
    has_access = bool(roles & allowed)
    is_admin = "manager" in roles
    return has_access, is_admin
