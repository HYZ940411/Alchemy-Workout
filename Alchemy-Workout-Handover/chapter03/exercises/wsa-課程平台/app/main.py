from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.walking_skeleton.api import router as walking_skeleton_router

app = FastAPI(
    title="WSA Course Platform",
    description="課程平台 API (Walking Skeleton)",
    version="1.0.0",
)

# CORS 設定
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Walking skeleton 相關的路由
app.include_router(walking_skeleton_router, prefix="/api", tags=["messages"])

@app.get("/health")
def health_check():
    """健康檢查 endpoint"""
    return {"status": "ok"}

@app.get("/")
def root():
    """根路徑"""
    return {"message": "WSA Course Platform API", "version": "1.0.0"}
