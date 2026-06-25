from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.auth import CurrentUser, authenticate_user, create_token
from api.database import ControlSessionLocal

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


@router.get("/me")
def get_me(current_user: CurrentUser) -> dict:
    return {"email": current_user}
