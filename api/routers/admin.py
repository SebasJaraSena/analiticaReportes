from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.auth import CurrentAdmin, get_current_admin, hash_password
from api.database import ControlSessionLocal
from api.models import ReporteUser

router = APIRouter(prefix="/api/admin", tags=["admin"])


def get_db():
    db = ControlSessionLocal()
    try:
        yield db
    finally:
        db.close()


class CreateUserRequest(BaseModel):
    email: str
    username: str
    password: str
    is_admin: bool = False


class UpdateUserRequest(BaseModel):
    password: str | None = None
    is_admin: bool | None = None
    is_active: bool | None = None


@router.get("/users")
def list_users(_: CurrentAdmin, db: Session = Depends(get_db)) -> list[dict]:
    users = db.query(ReporteUser).order_by(ReporteUser.id).all()
    return [
        {
            "id": u.id,
            "email": u.email,
            "username": u.username,
            "is_admin": u.is_admin,
            "is_active": u.is_active,
            "created_at": u.created_at.isoformat() if u.created_at else None,
        }
        for u in users
    ]


@router.post("/users", status_code=201)
def create_user(
    body: CreateUserRequest,
    _: CurrentAdmin,
    db: Session = Depends(get_db),
) -> dict:
    if db.query(ReporteUser).filter(ReporteUser.email == body.email).first():
        raise HTTPException(status_code=409, detail="Ya existe un usuario con ese correo.")
    if db.query(ReporteUser).filter(ReporteUser.username == body.username).first():
        raise HTTPException(status_code=409, detail="Ya existe un usuario con ese nombre de usuario.")
    user = ReporteUser(
        email=body.email,
        username=body.username,
        hashed_password=hash_password(body.password),
        is_admin=body.is_admin,
        is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return {"id": user.id, "email": user.email, "username": user.username, "is_admin": user.is_admin}


@router.put("/users/{user_id}")
def update_user(
    user_id: int,
    body: UpdateUserRequest,
    _: CurrentAdmin,
    db: Session = Depends(get_db),
) -> dict:
    user = db.get(ReporteUser, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")
    if body.password is not None:
        user.hashed_password = hash_password(body.password)
    if body.is_admin is not None:
        user.is_admin = body.is_admin
    if body.is_active is not None:
        user.is_active = body.is_active
    db.commit()
    return {
        "id": user.id,
        "email": user.email,
        "username": user.username,
        "is_admin": user.is_admin,
        "is_active": user.is_active,
    }


@router.delete("/users/{user_id}")
def delete_user(
    user_id: int,
    _: CurrentAdmin,
    db: Session = Depends(get_db),
) -> dict:
    user = db.get(ReporteUser, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")
    db.delete(user)
    db.commit()
    return {"ok": True}
