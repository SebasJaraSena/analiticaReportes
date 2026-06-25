"""Standalone JWT auth for the reports API."""
from __future__ import annotations

import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from api.config import settings
from api.database import ControlSessionLocal
from api.models import ReporteUser

logger = logging.getLogger(__name__)

_bearer = HTTPBearer(auto_error=False)
_pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")

TOKEN_EXPIRE_HOURS = 8


def hash_password(plain: str) -> str:
    return _pwd.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    return _pwd.verify(plain, hashed)


def create_token(email: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(hours=TOKEN_EXPIRE_HOURS)
    return jwt.encode(
        {"sub": email, "exp": expire},
        settings.secret_key,
        algorithm="HS256",
    )


def authenticate_user(db: Session, username: str, password: str) -> ReporteUser | None:
    user = (
        db.query(ReporteUser)
        .filter(
            (ReporteUser.username == username) | (ReporteUser.email == username)
        )
        .first()
    )
    if user is None or not user.is_active:
        return None
    if not verify_password(password, user.hashed_password):
        return None
    return user


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> str:
    """Validate Bearer JWT and return the user's email."""
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="No autenticado. Inicia sesión primero.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.secret_key,
            algorithms=["HS256"],
        )
    except JWTError as exc:
        logger.debug("JWT validation failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sesión expirada o token inválido.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    email = payload.get("sub")
    if not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token sin identidad.",
        )
    return email


CurrentUser = Annotated[str, Depends(get_current_user)]


def get_current_admin(current_user: str = Depends(get_current_user)) -> str:
    """Require the current user to be an admin."""
    db = ControlSessionLocal()
    try:
        user = db.query(ReporteUser).filter(ReporteUser.email == current_user).first()
        if user is None or not user.is_admin:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Se requieren permisos de administrador.",
            )
        return current_user
    finally:
        db.close()


CurrentAdmin = Annotated[str, Depends(get_current_admin)]


def seed_admin_user() -> None:
    """Create/update admin user from env vars on startup."""
    email = os.getenv("REPORTES_ADMIN_EMAIL", "")
    password = os.getenv("REPORTES_ADMIN_PASSWORD", "")
    username = os.getenv("REPORTES_ADMIN_USERNAME", "admin")
    if not email or not password:
        return
    db = ControlSessionLocal()
    try:
        user = db.query(ReporteUser).filter(ReporteUser.email == email).first()
        if user is None:
            user = ReporteUser(
                email=email,
                username=username,
                hashed_password=hash_password(password),
                is_active=True,
                is_admin=True,
            )
            db.add(user)
            logger.info("Admin user created: %s", email)
        else:
            user.hashed_password = hash_password(password)
            user.is_active = True
            user.is_admin = True
            logger.info("Admin user updated: %s", email)
        db.commit()
    except Exception as exc:
        db.rollback()
        if "already exists" in str(exc).lower() or "unique" in str(exc).lower():
            logger.debug("Admin user already exists (race on startup): %s", email)
        else:
            logger.exception("Failed to seed admin user.")
    finally:
        db.close()
