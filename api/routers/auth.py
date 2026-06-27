import secrets

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.auth import CurrentUser, authenticate_user, create_token, hash_password
from api.database import ControlSessionLocal
from api.models import ReporteUser
from api.moodle_auth import check_user_access, get_moodle_token, get_moodle_user_info, get_moodle_user_info_by_token

router = APIRouter(prefix="/api/auth", tags=["auth"])


def get_db():
    db = ControlSessionLocal()
    try:
        yield db
    finally:
        db.close()


class LoginRequest(BaseModel):
    username: str
    password: str


@router.post("/login")
def login(body: LoginRequest, db: Session = Depends(get_db)) -> dict:
    user = authenticate_user(db, body.username, body.password)
    if user is None:
        raise HTTPException(status_code=401, detail="Usuario o contraseña incorrectos.")
    return {"access_token": create_token(user.email), "token_type": "bearer"}


@router.post("/moodle-login")
def moodle_login(body: LoginRequest, db: Session = Depends(get_db)) -> dict:
    """SSO via Moodle Web Services. Auto-creates local user on first login."""
    try:
        wstoken = get_moodle_token(body.username, body.password)
        moodle_user = get_moodle_user_info(wstoken)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail=str(exc))
    except ConnectionError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    email = moodle_user["email"]
    username = moodle_user["username"]
    userid = moodle_user["userid"]

    has_access, is_admin = check_user_access(userid)
    if not has_access:
        raise HTTPException(
            status_code=403,
            detail="No tienes permiso para acceder al sistema de reportes. Contacta al administrador.",
        )

    user = (
        db.query(ReporteUser)
        .filter((ReporteUser.email == email) | (ReporteUser.username == username))
        .first()
    )

    if user is None:
        user = ReporteUser(
            email=email,
            username=username,
            hashed_password=hash_password(secrets.token_hex(32)),
            is_active=True,
            is_admin=is_admin,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    elif not user.is_active:
        raise HTTPException(status_code=401, detail="Usuario inactivo en el sistema de reportes.")
    else:
        # Sync admin status from Moodle on every login
        if user.is_admin != is_admin:
            user.is_admin = is_admin
            db.commit()

    return {"access_token": create_token(user.email), "token_type": "bearer"}


@router.get("/moodle-autologin")
def moodle_autologin(token: str = Query(...), db: Session = Depends(get_db)):
    """Auto-login from Moodle plugin redirect. Validates Moodle wstoken → issues JWT → redirects frontend."""
    try:
        moodle_user = get_moodle_user_info_by_token(token)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail=str(exc))
    except ConnectionError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    email = moodle_user["email"]
    username = moodle_user["username"]
    userid = moodle_user["userid"]

    has_access, is_admin = check_user_access(userid)
    if not has_access:
        raise HTTPException(status_code=403, detail="Sin permiso para acceder al sistema de reportes.")

    user = (
        db.query(ReporteUser)
        .filter((ReporteUser.email == email) | (ReporteUser.username == username))
        .first()
    )
    if user is None:
        user = ReporteUser(
            email=email,
            username=username,
            hashed_password=hash_password(secrets.token_hex(32)),
            is_active=True,
            is_admin=is_admin,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    elif not user.is_active:
        raise HTTPException(status_code=401, detail="Usuario inactivo.")
    else:
        if user.is_admin != is_admin:
            user.is_admin = is_admin
            db.commit()

    jwt = create_token(user.email)
    # Return HTML that stores JWT in localStorage and redirects to app root
    html = f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Ingresando...</title></head>
<body>
<script>
  localStorage.setItem('rz_token', '{jwt}');
  localStorage.setItem('rz_email', '{email}');
  window.location.replace('/');
</script>
<p>Redirigiendo...</p>
</body>
</html>"""
    return HTMLResponse(content=html)


@router.post("/logout")
def logout(current_user: CurrentUser, db: Session = Depends(get_db)) -> dict:
    """Invalidate Moodle wstoken for this user and return Moodle logout URL."""
    from api.moodle_auth import revoke_moodle_token
    revoke_moodle_token(current_user)
    from api.config import settings
    return {"moodle_logout_url": f"{settings.moodle_public_url}/login/logout.php"}


@router.get("/me")
def get_me(current_user: CurrentUser) -> dict:
    return {"email": current_user}
